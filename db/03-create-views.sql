-- View to list all friends for a user (shows each friendship from both perspectives)
CREATE OR REPLACE VIEW api.user_friends AS
  SELECT user_id_1 AS user_id, user_id_2 AS friend_id, created_at FROM friendships
  UNION
  SELECT user_id_2 AS user_id, user_id_1 AS friend_id, created_at FROM friendships;

-- Create a users view
CREATE OR REPLACE VIEW api.users AS
    SELECT
        id,
        email,
        name,
        created_at
    FROM public.users;