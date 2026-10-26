-- Demo data. Users get their password hash from the API on first start (password: Sentinel!2026).

-- ------------------------------------------------ roles & permissions (matrix from the spec)
INSERT INTO iam.role (id, name, tier, description) VALUES
 ('super_admin',     'Platform Super-Admin',          0, 'Vendor / central IT'),
 ('policy_admin',    'Security / Policy Admin',       1, 'CISO office'),
 ('agency_admin',    'Agency Administrator',          2, 'Agency IT lead'),
 ('site_admin',      'Site Administrator',            3, 'Site engineer'),
 ('supervisor',      'Supervisor / Incident Cmdr',    4, 'Control room supervisor'),
 ('operator',        'Operator',                      5, 'Control room operator'),
 ('investigator',    'Investigator / Forensics',      6, 'Case-scoped analyst'),
 ('exec_viewer',     'Executive Viewer',              7, 'Leadership dashboards'),
 ('auditor',         'Auditor',                       8, 'Read-only compliance'),
 ('service_account', 'Service / Integration Account', 9, 'Third-party systems');

INSERT INTO iam.role_permission (role_id, permission)
SELECT 'super_admin', p FROM unnest(ARRAY[
 'video.live','video.ptz','video.playback','video.export','video.unmask','alarm.handle','geo.view','telemetry.view',
 'rules.edit','device.create','device.configure','firmware.campaign','cert.manage','user.manage','policy.manage',
 'storage.policy','wall.control','health.view','audit.read','breakglass']) p;

INSERT INTO iam.role_permission (role_id, permission)
SELECT r, p FROM (VALUES
 ('policy_admin',    ARRAY['cert.manage','user.manage','policy.manage','storage.policy','health.view','audit.read']),
 ('agency_admin',    ARRAY['video.live','video.ptz','video.playback','video.export','video.unmask','alarm.handle','geo.view','telemetry.view','rules.edit','device.create','device.configure','firmware.campaign','cert.manage','user.manage','storage.policy','wall.control','health.view','audit.read','breakglass']),
 ('site_admin',      ARRAY['video.live','video.ptz','video.playback','video.export','alarm.handle','geo.view','telemetry.view','rules.edit','device.create','device.configure','firmware.campaign','cert.manage','user.manage','storage.policy','wall.control','health.view','audit.read','breakglass']),
 ('supervisor',      ARRAY['video.live','video.ptz','video.playback','video.export','video.unmask','alarm.handle','geo.view','telemetry.view','rules.edit','wall.control','health.view','breakglass']),
 ('operator',        ARRAY['video.live','video.ptz','video.playback','alarm.handle','geo.view','telemetry.view','wall.control','health.view']),
 ('investigator',    ARRAY['video.live','video.playback','video.export','video.unmask','alarm.handle','geo.view','telemetry.view']),
 ('exec_viewer',     ARRAY['video.live','geo.view','telemetry.view','wall.control','health.view']),
 ('auditor',         ARRAY['health.view','audit.read']),
 ('service_account', ARRAY['video.live','video.playback','alarm.handle','geo.view','telemetry.view','device.create','device.configure','health.view'])
) v(r, perms), unnest(v.perms) p;

-- ------------------------------------------------ sites (Abu Dhabi demo; coordinates approximate)
INSERT INTO inventory.site (id, name, kind, node_path, geom, wan_mbps) VALUES
 ('hq', 'Main DC - Command Center',  'main', 'sentinel.hq',            ST_SetSRID(ST_MakePoint(54.3773, 24.4539),4326), 0),
 ('portgate', 'Khalifa Port Gate',           'edge', 'sentinel.west.portgate', ST_SetSRID(ST_MakePoint(54.6444, 24.8083),4326), 6.4),
 ('airport', 'Zayed International Airport',        'edge', 'sentinel.west.airport',  ST_SetSRID(ST_MakePoint(54.6511, 24.4330),4326), 7.1),
 ('metro', 'Al Wahda Transit Hub',         'edge', 'sentinel.west.metro',    ST_SetSRID(ST_MakePoint(54.3720, 24.4780),4326), 5.9),
 ('refinery', 'Mussafah Industrial Complex',          'edge', 'sentinel.west.refinery', ST_SetSRID(ST_MakePoint(54.4950, 24.3530),4326), 5.2),
 ('toll', 'Maqta Bridge Toll Gate',        'edge', 'sentinel.west.toll',     ST_SetSRID(ST_MakePoint(54.5030, 24.4090),4326), 4.8);

-- ------------------------------------------------ devices, FOVs, geofences
DO $$
DECLARE
  s record; i int; g geography; h double precision; did uuid; lbl text;
BEGIN
  FOR s IN SELECT id, node_path, geom FROM inventory.site WHERE kind = 'edge' LOOP
    -- 24 cameras on a grid (~90 m pitch)
    FOR i IN 1..24 LOOP
      g := ST_SetSRID(ST_MakePoint(ST_X(s.geom) + ((i-1) % 6 - 2.5) * 0.0009,
                                   ST_Y(s.geom) + ((i-1) / 6 - 1.5) * 0.0009), 4326)::geography;
      h := (i * 37) % 360;
      lbl := 'cam' || lpad(i::text, 3, '0');
      INSERT INTO inventory.device (site_id, kind, name, vendor, model, firmware, status, ip, heading, node_path, geom, last_seen, attrs, cert_serial, cert_expires)
      VALUES (s.id, 'camera', upper(s.id) || '-' || lbl,
              (ARRAY['Axis','Hanwha','Bosch','Hikvision'])[1 + i % 4],
              (ARRAY['Q6135-LE','XNP-9300RW','MIC-7100','DS-2DF9C'])[1 + i % 4],
              (ARRAY['11.9.60','2.21.1','8.9.3'])[1 + i % 3],
              CASE WHEN i % 17 = 0 THEN 'offline' ELSE 'active' END,
              ('10.' || (10 + (ascii(substr(s.id,1,1)) % 40)) || '.1.' || (10 + i))::inet,
              h, s.node_path || lbl, g::geometry, now(),
              jsonb_build_object('codec', CASE WHEN i % 5 = 0 THEN 'H.264' ELSE 'H.265' END, 'resolution', CASE WHEN i % 3 = 0 THEN '8MP' ELSE '4MP' END, 'bitrateKbps', 2800 + (i % 4) * 400, 'ptz', i % 4 = 0),
              'SN' || upper(substr(md5(s.id || lbl), 1, 12)), now() + interval '90 days' - (i || ' days')::interval)
      RETURNING id INTO did;
      INSERT INTO geo.camera_fov (device_id, fov)
      VALUES (did, ST_SetSRID(ST_MakePolygon(ST_MakeLine(ARRAY[
        g::geometry,
        ST_Project(g, 70, radians(h - 30))::geometry,
        ST_Project(g, 78, radians(h))::geometry,
        ST_Project(g, 70, radians(h + 30))::geometry,
        g::geometry])), 4326));
    END LOOP;
    -- 2 radars
    FOR i IN 1..2 LOOP
      lbl := 'radar' || i;
      INSERT INTO inventory.device (site_id, kind, name, vendor, model, firmware, status, ip, node_path, geom, last_seen, attrs)
      VALUES (s.id, 'radar', upper(s.id) || '-RDR' || i, 'Axis', 'D2110-VE', '1.4.2', 'active',
              ('10.' || (10 + (ascii(substr(s.id,1,1)) % 40)) || '.2.' || (10 + i))::inet,
              s.node_path || lbl,
              ST_SetSRID(ST_MakePoint(ST_X(s.geom) + (i*2-3) * 0.0030, ST_Y(s.geom) + 0.0028), 4326), now(),
              jsonb_build_object('protocol', 'ASTERIX Cat 048', 'rangeM', 350));
    END LOOP;
    -- IoT gateway + 6 sensors
    INSERT INTO inventory.device (site_id, kind, name, vendor, model, firmware, status, ip, node_path, geom, last_seen)
    VALUES (s.id, 'iot_gateway', upper(s.id) || '-GW1', 'Advantech', 'WISE-6610', '3.2.0', 'active',
            ('10.' || (10 + (ascii(substr(s.id,1,1)) % 40)) || '.3.10')::inet, s.node_path || 'gw1', s.geom, now());
    FOR i IN 1..6 LOOP
      INSERT INTO inventory.device (site_id, kind, name, vendor, model, firmware, status, node_path, geom, last_seen, attrs)
      VALUES (s.id, 'sensor', upper(s.id) || '-SNS' || i, 'Generic', 'MQTT-SENSOR', '1.0.3', 'active',
              s.node_path || ('sns' || i),
              ST_SetSRID(ST_MakePoint(ST_X(s.geom) + (i-3.5) * 0.0007, ST_Y(s.geom) - 0.0030), 4326), now(),
              jsonb_build_object('metric', (ARRAY['temperature_c','vibration_mm_s','power_kw','humidity_pct','door_open','smoke_ppm'])[i]));
    END LOOP;
    -- restricted geofence
    INSERT INTO geo.geofence (site_id, name, restricted, geom)
    VALUES (s.id, 'Restricted Zone',  true,
      ST_Buffer(ST_SetSRID(ST_MakePoint(ST_X(s.geom) + 0.0016, ST_Y(s.geom) + 0.0012), 4326)::geography, 55)::geometry);
  END LOOP;
END $$;

-- ------------------------------------------------ demo users (fixed ids so grants can reference them)
INSERT INTO iam.app_user (id, username, display_name, agency) VALUES
 ('00000000-0000-0000-0000-000000000001', 'admin',        'Thirumal D (Super-Admin)',        'Central IT'),
 ('00000000-0000-0000-0000-000000000002', 'policy',       'Thirumal D (Policy Admin)',      'CISO Office'),
 ('00000000-0000-0000-0000-000000000003', 'agencyadmin',  'Thirumal D (Agency Admin)',        'Agency A'),
 ('00000000-0000-0000-0000-000000000004', 'siteadmin',    'Thirumal D (Site Admin)',    'Agency A'),
 ('00000000-0000-0000-0000-000000000005', 'supervisor',   'Thirumal D (Supervisor)',         'Agency A'),
 ('00000000-0000-0000-0000-000000000006', 'operator',     'Thirumal D (Operator)',         'Agency A'),
 ('00000000-0000-0000-0000-000000000007', 'investigator', 'Thirumal D (Investigator)',        'Agency A'),
 ('00000000-0000-0000-0000-000000000008', 'exec',         'Thirumal D (Exec Viewer)',   'Leadership'),
 ('00000000-0000-0000-0000-000000000009', 'auditor',      'Thirumal D (Auditor)',            'Compliance');

INSERT INTO iam.grant (user_id, role_id, node_path, effect) VALUES
 ('00000000-0000-0000-0000-000000000001', 'super_admin',  'sentinel',               'allow'),
 ('00000000-0000-0000-0000-000000000002', 'policy_admin', 'sentinel',               'allow'),
 ('00000000-0000-0000-0000-000000000003', 'agency_admin', 'sentinel',               'allow'),
 ('00000000-0000-0000-0000-000000000004', 'site_admin',   'sentinel.west.portgate', 'allow'),
 ('00000000-0000-0000-0000-000000000005', 'supervisor',   'sentinel',               'allow'),
 -- operator: two sites, plus a device-level deny that wins over the inherited allow
 ('00000000-0000-0000-0000-000000000006', 'operator',     'sentinel.west.portgate', 'allow'),
 ('00000000-0000-0000-0000-000000000006', 'operator',     'sentinel.west.airport',  'allow'),
 ('00000000-0000-0000-0000-000000000006', 'operator',     'sentinel.west.portgate.cam007', 'deny'),
 ('00000000-0000-0000-0000-000000000007', 'investigator', 'sentinel.west.metro',    'allow'),
 ('00000000-0000-0000-0000-000000000007', 'investigator', 'sentinel.west.refinery', 'allow'),
 ('00000000-0000-0000-0000-000000000008', 'exec_viewer',  'sentinel',               'allow'),
 ('00000000-0000-0000-0000-000000000009', 'auditor',      'sentinel',               'allow');

-- A few historical events so the console is not empty on first load
INSERT INTO ops.event (ts, site_id, device_id, node_path, severity, kind, message, geom)
SELECT now() - (n || ' minutes')::interval, d.site_id, d.id, d.node_path,
       (ARRAY['info','warning','major','critical'])[1 + n % 4],
       (ARRAY['motion','tamper','intrusion','device_offline'])[1 + n % 4],
       (ARRAY['Motion detected','Camera tamper suspected','Perimeter intrusion','Camera went offline'])[1 + n % 4],
       d.geom
FROM (SELECT row_number() OVER () AS n, * FROM inventory.device WHERE kind = 'camera' ORDER BY random() LIMIT 8) d;
