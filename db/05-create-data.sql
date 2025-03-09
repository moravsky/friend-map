-- Insert test users using api.register_user and get their IDs
DO $$
DECLARE
  user1_data json;
  user2_data json;
  user3_data json;
  user4_data json;
  user5_data json;
  
  user1_id bigint;
  user2_id bigint;
  user3_id bigint;
  user4_id bigint;
  user5_id bigint;
BEGIN
  -- Create test users and store their data
  user1_data := api.register_user('user1@example.com', 'password123', 'User One');
  user2_data := api.register_user('user2@example.com', 'password123', 'User Two');
  user3_data := api.register_user('user3@example.com', 'password123', 'User Three');
  user4_data := api.register_user('user4@example.com', 'password123', 'User Four');
  user5_data := api.register_user('user5@example.com', 'password123', 'User Five');
  
  -- Extract user IDs from the returned JSON (now bigint for snowflake IDs)
  user1_id := (user1_data->>'id')::bigint;
  user2_id := (user2_data->>'id')::bigint;
  user3_id := (user3_data->>'id')::bigint;
  user4_id := (user4_data->>'id')::bigint;
  user5_id := (user5_data->>'id')::bigint;

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