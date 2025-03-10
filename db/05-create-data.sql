-- Insert test users and location data
DO $$
DECLARE
  -- User data array (email, password, name)
  user_data text[][] := ARRAY[
    ARRAY['user1@example.com', 'password123', 'User One'],
    ARRAY['user2@example.com', 'password123', 'User Two'],
    ARRAY['user3@example.com', 'password123', 'User Three'],
    ARRAY['user4@example.com', 'password123', 'User Four'],
    ARRAY['user5@example.com', 'password123', 'User Five']
  ];
  
  -- Friendship pairs (user index pairs, 1-based)
  friendships int[][] := ARRAY[
    ARRAY[1, 2], -- User 1 is friends with User 2
    ARRAY[1, 3], -- User 1 is friends with User 3
    ARRAY[2, 4], -- User 2 is friends with User 4
    ARRAY[3, 5]  -- User 3 is friends with User 5
  ];
  
  -- Location areas with coordinates (name, lat, lon pairs)
  location_areas text[][] := ARRAY[
    -- University of Arizona area
    ARRAY['University Main Campus', '32.2319', '-110.9501'],
    ARRAY['Student Union', '32.2298', '-110.9490'],
    ARRAY['Arizona Stadium', '32.2280', '-110.9550'],
    ARRAY['Main Library', '32.2330', '-110.9480'],
    
    -- Downtown Tucson
    ARRAY['Downtown Center', '32.2217', '-110.9708'],
    ARRAY['Tucson Convention Center', '32.2226', '-110.9747'],
    ARRAY['Tucson Museum of Art', '32.2210', '-110.9690'],
    ARRAY['Hotel Congress', '32.2230', '-110.9720'],
    
    -- Tucson Mall area
    ARRAY['Tucson Mall', '32.2732', '-110.9792'],
    ARRAY['La Encantada', '32.2740', '-110.9800'],
    ARRAY['Foothills Mall', '32.2720', '-110.9780'],
    
    -- Tucson International Airport
    ARRAY['Airport Terminal', '32.1161', '-110.9410'],
    ARRAY['Airport Parking', '32.1170', '-110.9400'],
    
    -- Saguaro National Park East
    ARRAY['Visitor Center', '32.1792', '-110.7387'],
    ARRAY['Cactus Forest Drive', '32.1800', '-110.7400']
  ];
  
  -- Area assignments for each user (start index, count)
  user_areas int[][] := ARRAY[
    ARRAY[1, 4],   -- User 1: University area (indices 1-4)
    ARRAY[5, 4],   -- User 2: Downtown (indices 5-8)
    ARRAY[9, 3],   -- User 3: Mall area (indices 9-11)
    ARRAY[12, 2],  -- User 4: Airport (indices 12-13)
    ARRAY[14, 2]   -- User 5: Saguaro Park (indices 14-15)
  ];
  
  -- Variables
  user_ids bigint[] := ARRAY[0, 0, 0, 0, 0];
  user_result json;
  location_result json;
  i int;
  j int;
  k int;
  area_start int;
  area_count int;
  area_idx int;
  lat double precision;
  lon double precision;
  random_offset double precision;
  timestamp_offset interval;
BEGIN
  -- Create users
  FOR i IN 1..array_length(user_data, 1) LOOP
    -- Register user
    user_result := api.register_user(
      user_data[i][1],  -- email
      user_data[i][2],  -- password
      user_data[i][3]   -- name
    );
    
    -- Store user ID
    user_ids[i] := (user_result->>'id')::bigint;
  END LOOP;
  
  -- Create friendships
  FOR i IN 1..array_length(friendships, 1) LOOP
    PERFORM api.add_friend(
      user_ids[friendships[i][1]],  -- user_id_1
      user_ids[friendships[i][2]]   -- user_id_2
    );
  END LOOP;
  
  -- Add location history for each user
  FOR i IN 1..array_length(user_ids, 1) LOOP
    -- Get area assignment for this user
    area_start := user_areas[i][1];
    area_count := user_areas[i][2];
    
    -- Add 5 locations for each user
    FOR j IN 1..5 LOOP
      -- Select a location from the user's assigned area
      area_idx := area_start + ((j - 1) % area_count);
      
      -- Get base coordinates
      lat := location_areas[area_idx][2]::double precision;
      lon := location_areas[area_idx][3]::double precision;
      
      -- Add small random offset to make locations slightly different
      random_offset := (random() * 0.002) - 0.001; -- +/- ~100 meters
      lat := lat + random_offset;
      random_offset := (random() * 0.002) - 0.001;
      lon := lon + random_offset;
      
      -- Create timestamp with offset (older to newer)
      timestamp_offset := (5 - j) * interval '30 minutes';
      
      -- Add location
      location_result := api.add_location(
        user_ids[i],
        lat,
        lon,
        NULL, -- No geohash, will be generated
        now() - timestamp_offset
      );
    END LOOP;
  END LOOP;
  
  -- Output information about created users and locations
  RAISE NOTICE 'Created % users with IDs: % and added location history',
    array_length(user_ids, 1),
    array_to_string(user_ids, ', ');
END $$;