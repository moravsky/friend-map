-- Create a function to register users with SECURITY DEFINER
CREATE OR REPLACE FUNCTION api.register_user(
  email TEXT,
  password TEXT,
  name TEXT
) RETURNS json
SECURITY DEFINER
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

-- Flexible function to add a single location history record
-- Accepts either lat/lon or geohash
CREATE OR REPLACE FUNCTION api.add_location(
  user_id BIGINT,
  latitude DOUBLE DEFAULT NULL,
  longitude DOUBLE DEFAULT NULL,
  geohash TEXT DEFAULT NULL,
  recorded_at TIMESTAMPTZ DEFAULT now()
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  final_geohash TEXT;
  point_geom GEOMETRY;
  final_latitude DOUBLE;
  final_longitude DOUBLE;
  new_record RECORD;
BEGIN
  -- Validate user exists
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;
  
  -- Determine if we're using lat/lon or geohash
  IF geohash IS NOT NULL THEN
    -- Using geohash
    -- Validate geohash format (basic check)
    IF geohash !~ '^[0-9bcdefghjkmnpqrstuvwxyz]+$' THEN
      RAISE EXCEPTION 'Invalid geohash format';
    END IF;
    
    final_geohash := geohash;
    
    -- Extract lat/lon from geohash for the response
    point_geom := ST_GeomFromGeoHash(geohash, 10)::geometry;
    final_latitude := ST_Y(point_geom);
    final_longitude := ST_X(point_geom);
  ELSIF latitude IS NOT NULL AND longitude IS NOT NULL THEN
    -- Using lat/lon
    final_latitude := latitude;
    final_longitude := longitude;
    
    -- Generate geohash using PostGIS
    -- Step 1: Create a point geometry from longitude and latitude
    point_geom := ST_MakePoint(longitude, latitude);
    
    -- Step 2: Set the spatial reference system to WGS84 (SRID 4326)
    point_geom := ST_SetSRID(point_geom, 4326);
    
    -- Step 3: Convert the point to a geohash with precision 12
    final_geohash := ST_GeoHash(point_geom, 12);
  ELSE
    RAISE EXCEPTION 'Either geohash or both latitude and longitude must be provided';
  END IF;
  
  -- Insert location history record
  INSERT INTO public.location_history (
    id,
    user_id,
    geohash,
    recorded_at
  )
  VALUES (
    generate_snowflake_id(),
    user_id,
    final_geohash,
    recorded_at
  )
  RETURNING * INTO new_record;
  
  -- Return the created record
  RETURN json_build_object(
    'id', new_record.id,
    'user_id', new_record.user_id,
    'geohash', new_record.geohash,
    'latitude', final_latitude,
    'longitude', final_longitude,
    'recorded_at', new_record.recorded_at,
    'created_at', new_record.created_at
  );
END;
$$ LANGUAGE plpgsql;

-- Function to bulk add location history records for multiple users
-- Optimized for performance with large datasets
CREATE OR REPLACE FUNCTION api.bulk_add_locations(
  locations json
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  inserted_count INTEGER := 0;
  error_count INTEGER := 0;
  invalid_users TEXT[];
  invalid_formats TEXT[];
BEGIN
  -- Validate locations is an array
  IF json_typeof(locations) != 'array' THEN
    RAISE EXCEPTION 'Locations must be a JSON array';
  END IF;
  
  -- First, validate all users exist (in a single query for efficiency)
  WITH user_ids AS (
    SELECT DISTINCT (json_array_elements(locations)->>'user_id')::BIGINT AS user_id
  )
  SELECT array_agg(user_id::TEXT)
  INTO invalid_users
  FROM user_ids
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = user_id);
  
  IF array_length(invalid_users, 1) > 0 THEN
    RAISE EXCEPTION 'Invalid user IDs: %', array_to_string(invalid_users, ', ');
  END IF;
  
  -- Process records with geohash
  WITH geohash_data AS (
    SELECT
      generate_snowflake_id() AS id,
      (loc->>'user_id')::BIGINT AS user_id,
      loc->>'geohash' AS geohash,
      COALESCE((loc->>'recorded_at')::TIMESTAMPTZ, now()) AS recorded_at
    FROM json_array_elements(locations) AS loc
    WHERE loc->>'geohash' IS NOT NULL
      AND loc->>'geohash' ~ '^[0-9bcdefghjkmnpqrstuvwxyz]+$'
  )
  INSERT INTO public.location_history (id, user_id, geohash, recorded_at)
  SELECT id, user_id, geohash, recorded_at
  FROM geohash_data;
  
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  
  -- Process records with lat/lon
  WITH latlon_data AS (
    SELECT
      generate_snowflake_id() AS id,
      (loc->>'user_id')::BIGINT AS user_id,
      ST_GeoHash(
        ST_SetSRID(
          ST_MakePoint(
            (loc->>'longitude')::DOUBLE,
            (loc->>'latitude')::DOUBLE
          ),
          4326
        ),
        12
      ) AS geohash,
      COALESCE((loc->>'recorded_at')::TIMESTAMPTZ, now()) AS recorded_at
    FROM json_array_elements(locations) AS loc
    WHERE loc->>'latitude' IS NOT NULL
      AND loc->>'longitude' IS NOT NULL
      AND loc->>'geohash' IS NULL
  )
  INSERT INTO public.location_history (id, user_id, geohash, recorded_at)
  SELECT id, user_id, geohash, recorded_at
  FROM latlon_data;
  
  GET DIAGNOSTICS error_count = ROW_COUNT;
  inserted_count := inserted_count + error_count;
  error_count := 0;
  
  -- Count records that didn't have either geohash or lat/lon
  WITH invalid_data AS (
    SELECT
      loc->>'user_id' AS user_id
    FROM json_array_elements(locations) AS loc
    WHERE (loc->>'geohash' IS NULL OR loc->>'geohash' !~ '^[0-9bcdefghjkmnpqrstuvwxyz]+$')
      AND (loc->>'latitude' IS NULL OR loc->>'longitude' IS NULL)
  )
  SELECT COUNT(*)
  INTO error_count
  FROM invalid_data;
  
  -- Return summary of the operation
  RETURN json_build_object(
    'inserted_count', inserted_count,
    'error_count', error_count,
    'status', CASE WHEN error_count = 0 THEN 'success' ELSE 'partial_success' END
  );
END;
$$ LANGUAGE plpgsql;

-- Function to get location history for a user
CREATE OR REPLACE FUNCTION api.get_location_history(
  user_id BIGINT,
  start_time TIMESTAMPTZ DEFAULT now() - INTERVAL '24 hours',
  end_time TIMESTAMPTZ DEFAULT now(),
  limit_count INTEGER DEFAULT 100
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  -- Validate user exists
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;
  
  -- Query location history and decode geohashes using PostGIS
  WITH decoded_locations AS (
    SELECT
      lh.id,
      lh.geohash,
      lh.recorded_at,
      ST_Y(ST_GeomFromGeoHash(lh.geohash, 10)::geometry) AS latitude,
      ST_X(ST_GeomFromGeoHash(lh.geohash, 10)::geometry) AS longitude
    FROM public.location_history lh
    WHERE lh.user_id = user_id
      AND lh.recorded_at >= start_time
      AND lh.recorded_at <= end_time
    ORDER BY lh.recorded_at DESC
    LIMIT limit_count
  )
  SELECT json_agg(
    json_build_object(
      'id', dl.id,
      'geohash', dl.geohash,
      'latitude', dl.latitude,
      'longitude', dl.longitude,
      'recorded_at', dl.recorded_at
    )
  )
  INTO result
  FROM decoded_locations dl;
  
  -- Return the results
  RETURN json_build_object(
    'user_id', user_id,
    'start_time', start_time,
    'end_time', end_time,
    'count', json_array_length(COALESCE(result, '[]'::json)),
    'locations', COALESCE(result, '[]'::json)
  );
END;
$$ LANGUAGE plpgsql;

-- Function to find nearby users based on geohash prefix matching
CREATE OR REPLACE FUNCTION api.find_nearby_users(
  user_id BIGINT,
  geohash_precision INTEGER DEFAULT 6,  -- Geohash precision for proximity (lower = larger area)
  limit_count INTEGER DEFAULT 10
) RETURNS json
SECURITY DEFINER
AS $$
DECLARE
  user_geohash TEXT;
  geohash_prefix TEXT;
  result json;
BEGIN
  -- Validate user exists
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;
  
  -- Get the user's most recent location
  SELECT geohash INTO user_geohash
  FROM location_history
  WHERE user_id = user_id
  ORDER BY recorded_at DESC
  LIMIT 1;
  
  IF user_geohash IS NULL THEN
    RAISE EXCEPTION 'User has no location history';
  END IF;
  
  -- Get the prefix for proximity search
  geohash_prefix := LEFT(user_geohash, geohash_precision);
  
  -- Find nearby users
  WITH recent_locations AS (
    -- Get most recent location for each user
    SELECT DISTINCT ON (lh.user_id)
      lh.user_id,
      u.name,
      lh.geohash,
      lh.recorded_at,
      ST_Y(ST_GeomFromGeoHash(lh.geohash, 10)::geometry) AS latitude,
      ST_X(ST_GeomFromGeoHash(lh.geohash, 10)::geometry) AS longitude
    FROM location_history lh
    JOIN users u ON lh.user_id = u.id
    WHERE lh.user_id != user_id
      AND LEFT(lh.geohash, geohash_precision) = geohash_prefix
    ORDER BY lh.user_id, lh.recorded_at DESC
  )
  SELECT json_agg(
    json_build_object(
      'user_id', rl.user_id,
      'name', rl.name,
      'geohash', rl.geohash,
      'latitude', rl.latitude,
      'longitude', rl.longitude,
      'recorded_at', rl.recorded_at
    )
  )
  INTO result
  FROM recent_locations rl
  LIMIT limit_count;
  
  -- Return the results
  RETURN json_build_object(
    'user_id', user_id,
    'geohash_prefix', geohash_prefix,
    'geohash_precision', geohash_precision,
    'count', json_array_length(COALESCE(result, '[]'::json)),
    'nearby_users', COALESCE(result, '[]'::json)
  );
END;
$$ LANGUAGE plpgsql;