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

-- Create a continuous aggregate view for user locations by time bucket
CREATE MATERIALIZED VIEW user_locations_by_time
WITH (timescaledb.continuous) AS
SELECT
  time_bucket('5 minutes', recorded_at) AS bucket,
  user_id,
  MAX(recorded_at) AS latest_time,
  COUNT(*) AS location_count
FROM location_history
GROUP BY bucket, user_id;

-- Create a refresh policy to update the continuous aggregate every 5 seconds
SELECT add_continuous_aggregate_policy('user_locations_by_time',
  start_offset => INTERVAL '1 hour',
  end_offset => INTERVAL '0 seconds',
  schedule_interval => INTERVAL '5 seconds');

-- Create a view to get the latest location for each user
CREATE OR REPLACE VIEW latest_user_locations AS
SELECT
  lh.user_id,
  lh.geohash,
  lh.recorded_at,
  lh.id AS location_id
FROM location_history lh
INNER JOIN (
  SELECT
    user_id,
    MAX(recorded_at) AS max_recorded_at
  FROM location_history
  GROUP BY user_id
) latest ON lh.user_id = latest.user_id AND lh.recorded_at = latest.max_recorded_at;