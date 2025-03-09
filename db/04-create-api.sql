-- Create a function to register users with SECURITY DEFINER
CREATE OR REPLACE FUNCTION api.register_user(
  email TEXT,
  password TEXT,
  name TEXT
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  new_user public.users;
BEGIN
  -- Hash the password and insert the user
  INSERT INTO public.users (email, password_hash, name)
  VALUES (
    email,
    crypt(password, gen_salt('bf')),
    name
  )
  RETURNING * INTO new_user;
  
  -- Return user information (excluding password)
  RETURN json_build_object(
    'id', new_user.id,
    'email', new_user.email,
    'name', new_user.name,
    'created_at', new_user.created_at
  );
END;
$$ LANGUAGE plpgsql;

-- Function to add a friend
CREATE OR REPLACE FUNCTION api.add_friend(
  user_id_a BIGINT,
  user_id_b BIGINT
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  user1 BIGINT;
  user2 BIGINT;
BEGIN
  -- Validate users exist
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = user_id_a) THEN
    RAISE EXCEPTION 'First user does not exist';
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = user_id_b) THEN
    RAISE EXCEPTION 'Second user does not exist';
  END IF;
  
  -- Prevent self-friendship
  IF user_id_a = user_id_b THEN
    RAISE EXCEPTION 'Cannot create friendship with self';
  END IF;
  
  -- Order the user IDs to ensure consistent storage
  IF user_id_a < user_id_b THEN
    user1 := user_id_a;
    user2 := user_id_b;
  ELSE
    user1 := user_id_b;
    user2 := user_id_a;
  END IF;
  
  -- Check if friendship already exists
  IF EXISTS (SELECT 1 FROM friendships WHERE user_id_1 = user1 AND user_id_2 = user2) THEN
    RAISE EXCEPTION 'Friendship already exists between these users';
  END IF;
  
  -- Create the friendship
  INSERT INTO friendships (user_id_1, user_id_2)
  VALUES (user1, user2);
  
  RETURN json_build_object(
    'user_id_1', user1,
    'user_id_2', user2,
    'created_at', now()
  );
END;
$$ LANGUAGE plpgsql;

-- Function to remove a friend
CREATE OR REPLACE FUNCTION api.remove_friend(
  user_id_a BIGINT,
  user_id_b BIGINT
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  user1 BIGINT;
  user2 BIGINT;
BEGIN
  -- Order the user IDs to match storage
  IF user_id_a < user_id_b THEN
    user1 := user_id_a;
    user2 := user_id_b;
  ELSE
    user1 := user_id_b;
    user2 := user_id_a;
  END IF;
  
  -- Delete the friendship
  DELETE FROM friendships
  WHERE user_id_1 = user1 AND user_id_2 = user2;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No friendship found between these users';
  END IF;
  
  RETURN json_build_object(
    'user_id_1', user1,
    'user_id_2', user2,
    'status', 'deleted'
  );
END;
$$ LANGUAGE plpgsql;