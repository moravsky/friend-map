-- Create pgcrypto extension for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create a sequence for the increment part of the snowflake
DROP SEQUENCE IF EXISTS snowflake_seq;
CREATE SEQUENCE snowflake_seq CYCLE;

-- Snowflake ID generation function using sequence
-- Format: timestamp (41 bits) | node_id (10 bits) | sequence (12 bits)
CREATE OR REPLACE FUNCTION generate_snowflake_id(
    node_id INT DEFAULT 1  -- Node ID between 0 and 1023
) RETURNS BIGINT AS $$
DECLARE
    -- Custom epoch (January 1, 2023 UTC)
    epoch BIGINT := 1672531200000;
    time_ms BIGINT;
    seq_id INT;
    result BIGINT := 0;
BEGIN
    -- Get current timestamp in milliseconds since epoch
    time_ms := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - epoch;
    
    -- Get next value from sequence and ensure it fits in 12 bits (0-4095)
    seq_id := nextval('snowflake_seq') % 4096;
    
    -- Build the snowflake ID:
    -- time_ms (41 bits) | node_id (10 bits) | seq_id (12 bits)
    result := (time_ms << 22) | ((node_id % 1024) << 12) | seq_id;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Create your users table with snowflake IDs
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (
  id BIGINT PRIMARY KEY DEFAULT generate_snowflake_id(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Create friendships table (bi-directional)
DROP TABLE IF EXISTS friendships CASCADE;
CREATE TABLE friendships (
  user_id_1 BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_id_2 BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id_1, user_id_2),
  CHECK (user_id_1 < user_id_2) -- Ensure uniqueness and prevent self-friendship
);

-- Add index for faster friendship lookups
CREATE INDEX idx_friendships_user_id_1 ON friendships(user_id_1);
CREATE INDEX idx_friendships_user_id_2 ON friendships(user_id_2);

-- Create a function to register users with SECURITY DEFINER
CREATE OR REPLACE FUNCTION api.register_user(
  email TEXT,
  password TEXT,
  name TEXT
) RETURNS json
SECURITY DEFINER  -- This is the critical part
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

-- View to list all friends for a user (shows each friendship from both perspectives)
CREATE OR REPLACE VIEW api.user_friends AS
  SELECT user_id_1 AS user_id, user_id_2 AS friend_id, created_at FROM friendships
  UNION
  SELECT user_id_2 AS user_id, user_id_1 AS friend_id, created_at FROM friendships;

-- Create a view that doesn't expose password_hash
CREATE OR REPLACE VIEW api.users AS
    SELECT
        id,
        email,
        name,
        created_at
    FROM public.users;