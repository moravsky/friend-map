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

-- Create a continuous aggregate view for the latest location of each user
CREATE MATERIALIZED VIEW latest_user_locations
WITH (timescaledb.continuous) AS
SELECT DISTINCT ON (user_id) 
  user_id,
  geohash,
  recorded_at,
  id AS location_id
FROM location_history
ORDER BY user_id, recorded_at DESC;

-- Create a refresh policy to update the continuous aggregate every hour
SELECT add_continuous_aggregate_policy('latest_user_locations',
  start_offset => INTERVAL '1 hour',
  end_offset => INTERVAL '5 seconds',
  schedule_interval => INTERVAL '5 seconds');