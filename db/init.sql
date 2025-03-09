-- Create roles
CREATE ROLE anon LOGIN PASSWORD 'mysecretpassword';

-- Grant usage on the schema
GRANT USAGE ON SCHEMA api TO anon;

-- Grant select on all existing tables/views
GRANT SELECT ON ALL TABLES IN SCHEMA api TO anon;

-- Grant execute on all existing functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO anon;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA api
  GRANT SELECT ON TABLES TO anon;
  
ALTER DEFAULT PRIVILEGES IN SCHEMA api
  GRANT EXECUTE ON FUNCTIONS TO anon;