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

-- Enable extensions - order is important
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create location_history table for tracking user locations
DROP TABLE IF EXISTS location_history CASCADE;
CREATE TABLE location_history (
  id BIGINT NOT NULL DEFAULT generate_snowflake_id(),
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  geohash TEXT NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  -- Make the primary key a composite of id and recorded_at
  -- This is required for TimescaleDB hypertables with primary keys
  PRIMARY KEY (id, recorded_at)
);

-- Create indexes for faster location history queries
CREATE INDEX idx_location_history_user_id ON location_history(user_id);
CREATE INDEX idx_location_history_recorded_at ON location_history(recorded_at DESC);
CREATE INDEX idx_location_history_geohash ON location_history(geohash);
CREATE INDEX idx_location_history_geohash_prefix ON location_history(LEFT(geohash, 6));

-- Convert to hypertable partitioned by time
SELECT create_hypertable('location_history', 'recorded_at');

-- Set 30-day retention policy
SELECT add_retention_policy('location_history', INTERVAL '30 days');