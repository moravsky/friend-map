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