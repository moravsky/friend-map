-- Create api schema
DROP SCHEMA IF EXISTS api CASCADE;
CREATE SCHEMA api;

-- Create pgcrypto extension for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create your users table
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

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

-- Create a view that doesn't expose password_hash
CREATE OR REPLACE VIEW api.users AS
    SELECT
        id,
        email,
        name,
        created_at
    FROM public.users;