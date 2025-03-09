-- Insert test users using api.register_user and get their IDs
DO $$
DECLARE
  user1_data json;
  user2_data json;
  user3_data json;
  user4_data json;
  user5_data json;
  
  user1_id integer;
  user2_id integer;
  user3_id integer;
  user4_id integer;
  user5_id integer;
BEGIN
  -- Create test users and store their data
  user1_data := api.register_user('user1@example.com', 'password123', 'User One');
  user2_data := api.register_user('user2@example.com', 'password123', 'User Two');
  user3_data := api.register_user('user3@example.com', 'password123', 'User Three');
  user4_data := api.register_user('user4@example.com', 'password123', 'User Four');
  user5_data := api.register_user('user5@example.com', 'password123', 'User Five');
  
  -- Extract user IDs from the returned JSON
  user1_id := (user1_data->>'id')::integer;
  user2_id := (user2_data->>'id')::integer;
  user3_id := (user3_data->>'id')::integer;
  user4_id := (user4_data->>'id')::integer;
  user5_id := (user5_data->>'id')::integer;

  -- Create some friendships
  -- User 1 is friends with User 2 and User 3
  PERFORM api.add_friend(user1_id, user2_id);
  PERFORM api.add_friend(user1_id, user3_id);

  -- User 2 is also friends with User 4
  PERFORM api.add_friend(user2_id, user4_id);

  -- User 5 is friends with User 3
  PERFORM api.add_friend(user3_id, user5_id);
  
  -- Output some information about created users
  RAISE NOTICE 'Created users with IDs: %, %, %, %, %',
    user1_id, user2_id, user3_id, user4_id, user5_id;
END $$;