classdef BlueFTController < handle
    %BLUEFTCONTROLLER A class used to remote control the BlueFors Controller software.
    %
    %   MATLAB port of the Python class `BlueFTController` from
    %   blueftc.BlueforsController (see the BlueFTC Python package by
    %   Elias Ankerhold / Thomas Pfau). Structure, naming and behavior are
    %   kept as close as possible to the original.
    %
    %   NOTE ON NAMING: MATLAB identifiers cannot start with an underscore,
    %   so private helper methods that were named e.g. `_setup_logging` in
    %   Python are named `setup_logging` here and made private via
    %   `methods (Access = private)`. See README.md for the full mapping.
    %
    %   Properties
    %   ----------
    %   ip : string
    %       The IP address of the BlueFors Controller server.
    %   key : string
    %       The key used for the requests.
    %   port : double
    %       The port used for the requests.
    %   mixing_chamber_channel_id : double
    %       The channel ID of the mixing chamber.
    %   mixing_chamber_heater : string
    %       The heater mapping for the mixing chamber.
    %   debug : logical
    %       A flag used to set the log level.
    %   pid_config_path : string
    %       Path to file storing PID calibration table.
    %
    %   Methods
    %   -------
    %   get_channel_data(channel, target_value)
    %   get_channel_temperature(channel)
    %   get_channel_resistance(channel)
    %   get_mxc_temperature()
    %   get_mxc_resistance()
    %   get_mxc_heater_value(target)
    %   check_heater_value_synced(target)
    %   set_mxc_heater_value(target, value)
    %   get_mxc_heater_status()
    %   set_mxc_heater_status(newStatus)
    %   toggle_mxc_heater(status)
    %   get_mxc_heater_power()
    %   set_mxc_heater_power(power)
    %   get_mxc_heater_setpoint()
    %   set_mxc_heater_setpoint(temperature, use_pid_calib)
    %   get_mxc_heater_mode()
    %   set_mxc_heater_mode(toggle)
    %   get_mxc_heater_pid_config()
    %   set_mxc_heater_pid_config(p, i, d)
    %   get_maxigauge_channel(channel)

    properties
        ip                          char    % The IP address of the BlueFors Controller server.
        key                         char    % The key used for the requests.
        port                        double  % The port used for the requests.
        mixing_chamber_channel_id   double  % The channel ID of the mixing chamber.
        mixing_chamber_heater       char    % The heater mapping for the mixing chamber.
        debug                       logical % A flag used to set the log level.
        pid_config_path             char    % Path to file storing PID calibration table.
    end

    properties (Access = private)
        has_mxc             (1,1) logical = false   % Whether a mixing chamber channel is configured.
        valid_pid_config    (1,1) logical = false   % Whether a PID calibration table was loaded.
        pid_calib_setpoints                         % PID calibration setpoints (Kelvin), sorted.
        pid_calib_pid                                % PID calibration [P I D] rows, sorted.
        maxigauge_pressure  (1,1) logical = false   % Toggles Pfeiffer Maxigauge pressure reading.
        emulate             (1,1) logical = false   % Toggles emulation mode.
        log_file            char = 'bluefors.log'        % Log file path.
        log_state_file      char = 'bluefors.log.state'  % Bookkeeping file for weekly log rotation.
    end

    methods
        function obj = BlueFTController(args)
            %BLUEFTCONTROLLER Construct a BlueFTController object.
            %
            %   Call using name=value arguments, mirroring the Python
            %   constructor's keyword arguments, e.g.:
            %
            %       controller = blueftc.BlueFTController(ip=IP_ADDRESS, ...
            %           port=PORT_NUMBER, key=API_KEY, ...
            %           mixing_chamber_channel_id=MXC_ID, ...
            %           mixing_chamber_heater_id=HEATER_ID);
            %
            %   Parameters
            %   ----------
            %   ip : string
            %       The IP address of the BlueFors Temperature Controller.
            %   mixing_chamber_channel_id : double, optional
            %       The channel ID of the mixing chamber (default is []).
            %   mixing_chamber_heater_id : double, optional
            %       The heater ID of the mixing chamber heater (default is []).
            %   port : double, optional
            %       The port used for the requests (default is 49098).
            %   key : string, optional
            %       The key used for the requests (default is missing).
            %   debug : logical, optional
            %       A flag used to set the log level (default is false).
            %   pid_calib_path : string, optional
            %       Filepath to csv file storing PID calibration table
            %       (default is missing).
            %   activate_maxigauge_reading : logical, optional
            %       Toggles activation of pressure reading for Pfeiffer
            %       Maxigauge units (default is false).
            %   emulate : logical, optional
            %       Toggles emulation mode, where no actual communication
            %       with the control software is taking place (default is false).
            arguments
                args.ip (1,1) string
                args.mixing_chamber_channel_id double = []
                args.mixing_chamber_heater_id double = []
                args.port (1,1) double = 49098
                args.key string = missing
                args.debug (1,1) logical = false
                args.pid_calib_path string = missing
                args.activate_maxigauge_reading (1,1) logical = false
                args.emulate (1,1) logical = false
            end

            obj.ip = char(args.ip);

            if ismissing(args.key)
                obj.key = '';
            else
                obj.key = char(args.key);
            end

            obj.port = args.port;
            obj.mixing_chamber_channel_id = args.mixing_chamber_channel_id;

            if isempty(args.mixing_chamber_heater_id)
                heaterStr = 'None'; % mirrors Python f-string of None
            else
                heaterStr = num2str(args.mixing_chamber_heater_id);
            end
            obj.mixing_chamber_heater = ['driver.bftc.data.heaters.heater_' heaterStr];

            obj.debug = args.debug;

            if ismissing(args.pid_calib_path) || strlength(args.pid_calib_path) == 0
                obj.pid_config_path = '';
            else
                obj.pid_config_path = char(args.pid_calib_path);
            end

            obj.setup_logging();

            obj.has_mxc = ~isempty(args.mixing_chamber_channel_id);
            obj.valid_pid_config = false;
            obj.pid_calib_setpoints = [];
            obj.pid_calib_pid = [];
            obj.maxigauge_pressure = args.activate_maxigauge_reading;
            obj.emulate = args.emulate;

            obj.load_pid_config();
        end
    end

    methods (Access = private)

        function setup_logging(obj)
            %SETUP_LOGGING Set up logging for this instance.
            %
            %   This is a simplified analogue of Python's `logging` module
            %   setup in `_setup_logging`, which created a logger with a
            %   TimedRotatingFileHandler (rotating every Sunday, keeping 12
            %   backups) and a console StreamHandler. MATLAB has no
            %   equivalent built-in logging framework, so this method just
            %   ensures the log file is rotated if needed; actual message
            %   formatting and writing happens in `log_message`.
            obj.rotate_log_if_needed();
        end

        function rotate_log_if_needed(obj)
            %ROTATE_LOG_IF_NEEDED Rotate the log file weekly (on Sundays).
            %   Approximates Python's TimedRotatingFileHandler(when='W6',
            %   interval=1, backupCount=12): rotate at most once per Sunday
            %   and keep the last 12 rotated files.
            todayStr = char(datetime('now', 'Format', 'yyyy-MM-dd'));
            isSunday = weekday(datetime('now')) == 1;

            lastRotation = '';
            if isfile(obj.log_state_file)
                lastRotation = strtrim(fileread(obj.log_state_file));
            end

            if isSunday && ~strcmp(lastRotation, todayStr) && isfile(obj.log_file)
                rotatedName = sprintf('%s.%s', obj.log_file, todayStr);
                if ~isfile(rotatedName)
                    movefile(obj.log_file, rotatedName);
                end
                fid = fopen(obj.log_state_file, 'w');
                if fid ~= -1
                    fprintf(fid, '%s', todayStr);
                    fclose(fid);
                end
                obj.prune_old_logs();
            end
        end

        function prune_old_logs(obj)
            %PRUNE_OLD_LOGS Keep only the 12 most recent rotated log files
            %   (mirrors Python's backupCount=12).
            files = dir([obj.log_file '.*']);
            if numel(files) > 12
                [~, idx] = sort([files.datenum]);
                files = files(idx);
                toDelete = files(1:end-12);
                for k = 1:numel(toDelete)
                    delete(fullfile(toDelete(k).folder, toDelete(k).name));
                end
            end
        end

        function log_message(obj, level, msg)
            %LOG_MESSAGE Log a message at the given level ('DEBUG', 'INFO',
            %   'WARNING', 'ERROR'), mirroring calls to self.logger.debug/
            %   info/warning/error(...) in the Python original. Writes to
            %   both the console and the rotating log file.
            levelValues = containers.Map({'DEBUG', 'INFO', 'WARNING', 'ERROR'}, {10, 20, 30, 40});
            if obj.debug
                threshold = 10;
            else
                threshold = 20;
            end
            if levelValues(level) < threshold
                return
            end

            obj.rotate_log_if_needed();

            st = dbstack(2);
            if ~isempty(st)
                callerName = st(1).name;
                callerLine = st(1).line;
            else
                callerName = 'BlueFTController';
                callerLine = 0;
            end

            ts = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss,SSS'));
            fprintf('%s :-- %s --: %s\n', ts, level, msg);

            fid = fopen(obj.log_file, 'a');
            if fid ~= -1
                fprintf(fid, '%s %-6s - %s() L%-4d - %s\n', ts, level, callerName, callerLine, msg);
                fclose(fid);
            end
        end

        function load_pid_config(obj)
            %LOAD_PID_CONFIG Load a PID calibration table from a csv file.
            %   Must be formatted with a header row and four columns:
            %   [setpoint, p, i, d].
            if ~isempty(obj.pid_config_path)
                if ~isfile(obj.pid_config_path)
                    warning('blueftc:PIDConfigFileNotFound', ...
                        ['Encountered error while loading pid config file: file not found: %s\n' ...
                         'Continuing without automatic PID setpoint parameter adjustment.'], ...
                        obj.pid_config_path);
                    return
                end
                try
                    pid_config = readmatrix(obj.pid_config_path, 'NumHeaderLines', 1);
                    obj.pid_calib_setpoints = pid_config(:, 1);
                    obj.pid_calib_pid = pid_config(:, 2:4);
                    [obj.pid_calib_setpoints, sortind] = sort(obj.pid_calib_setpoints);
                    obj.pid_calib_setpoints = obj.pid_calib_setpoints * 1e-3;
                    obj.pid_calib_pid = obj.pid_calib_pid(sortind, :);
                    obj.valid_pid_config = true;

                    obj.log_message('INFO', sprintf('PID calibration loaded from %s', obj.pid_config_path));
                catch ex
                    warning('blueftc:PIDConfigLoadError', ...
                        ['Encountered error while loading pid config file: %s\n' ...
                         'Continuing without automatic PID setpoint parameter adjustment.'], ...
                        ex.message);
                end
            end
        end

        function fname = data_key_field(~, device, target)
            %DATA_KEY_FIELD Compute the valid MATLAB struct field name
            %   corresponding to the JSON key "<device>.<target>", since
            %   MATLAB struct field names cannot contain dots. jsondecode
            %   sanitizes such keys internally using the same rules as
            %   matlab.lang.makeValidName, so we use that to look values back up.
            fname = matlab.lang.makeValidName(sprintf('%s.%s', device, target));
        end

        function value = handle_status_response(obj, status, target, set_flag)
            %HANDLE_STATUS_RESPONSE Handle possible status values returned
            %   from the control software.
            %   (Named `set_flag` here instead of Python's `set`, which is
            %   not a safe identifier to reuse in MATLAB.)
            %
            %   Returns
            %   -------
            %   value : double
            %       0 for 'INVALID'/'DISCONNECTED'/unrecognized status,
            %       1 for 'CHANGED'/'SYNCHRONIZED'/'INDEPENDENT',
            %       2 for 'QUEUED'.
            arguments
                obj
                status (1,1) string
                target (1,1) string
                set_flag (1,1) logical = false
            end

            if set_flag
                info = sprintf(" raised while setting '%s'", target);
            else
                info = '';
            end

            switch status
                case 'INVALID'
                    fprintf('Warning%s: The target value ''%s'' is invalid!\n', info, target);
                    value = 0;
                case 'CHANGED'
                    value = 1;
                case 'DISCONNECTED'
                    fprintf('Warning%s: The target device is disconnected! The target value ''%s'' is not valid.\n', info, target);
                    value = 0;
                case 'QUEUED'
                    fprintf(['Warning%s: The target value ''%s'' has been marked as ''QUEUED'' ' ...
                        'and might not be synchronized between control software and physical device! Verify again.\n'], info, target);
                    value = 2;
                case 'SYNCHRONIZED'
                    value = 1;
                case 'INDEPENDENT'
                    value = 1;
                otherwise
                    fprintf('Warning%s: Received invalid status response from control software. ''%s'' is not a valid status.\n', info, status);
                    value = 0;
            end
        end

        function status = get_synchronization_status(obj, data, device, target)
            %GET_SYNCHRONIZATION_STATUS Get the synchronization status from
            %   a data response.
            try
                key = obj.data_key_field(device, target);
                status = data.data.(key).content.latest_valid_value.status;
            catch
                obj.log_message('WARNING', 'Could not verify synchronization status');
                status = 'INVALID';
            end
        end

        function value = get_value_from_data_response(obj, data, device, target)
            %GET_VALUE_FROM_DATA_RESPONSE Get the value from a data response.
            %   Returns false if the synchronization status cannot be verified.
            try
                obj.handle_status_response(obj.get_synchronization_status(data, device, target), target, false);
                key = obj.data_key_field(device, target);
                value = data.data.(key).content.latest_valid_value.value;
            catch
                obj.log_message('WARNING', 'Could not verify synchronization status');
                value = false;
            end
        end

        function response = get_value_request(obj, device, target)
            %GET_VALUE_REQUEST Get the values currently in the Controller
            %   config for the given device via an HTTP GET request.
            if isempty(obj.key)
                throw(blueftc.PIDConfigException('No key provided for value request.'));
            end

            requestPath = sprintf('https://%s:%d/values/%s/%s/?prettyprint=1&key=%s', ...
                obj.ip, obj.port, strrep(device, '.', '/'), target, obj.key);

            if ~obj.emulate
                obj.log_message('DEBUG', sprintf('GET: %s', requestPath));
                try
                    httpRequest = matlab.net.http.RequestMessage;
                    uri = matlab.net.URI(requestPath);
                    % 'VerifyServerName', false mirrors requests' verify=False,
                    % since the server has a self-signed certificate.
                    options = matlab.net.http.HTTPOptions('ConnectTimeout', 10, 'VerifyServerName', false);
                    resp = send(httpRequest, uri, options);
                    if double(resp.StatusCode) >= 400
                        error('blueftc:HTTPError', 'HTTP request failed with status %d', double(resp.StatusCode));
                    end
                    response = jsondecode(char(resp.Body.Data));
                catch err
                    % We return data that indicates NaN and has an ERROR
                    % status (also otherwise not valid), mirroring the
                    % Python exception-handling branch exactly (including
                    % its quirk of not nesting under the device.target key).
                    obj.log_message('ERROR', sprintf('Error: %s', err.message));
                    response = struct('data', struct('content', struct('latest_valid_value', ...
                        struct('value', NaN, 'status', 'ERROR'))));
                end
            else
                obj.log_message('DEBUG', sprintf('EMULATED, GET: %s', requestPath));
                key = obj.data_key_field(device, target);
                mockValue = randi([0, 100]);
                inner = struct();
                inner.(key) = struct('content', struct('latest_valid_value', ...
                    struct('value', mockValue, 'status', 'SYNCHRONIZED')));
                response = struct('data', inner);
                obj.log_message('DEBUG', sprintf('EMULATED, RESPONSE: %s', jsonencode(response)));
            end
        end

        function response = set_value_request(obj, device, target, value)
            %SET_VALUE_REQUEST Set a given target value for a given target
            %   device via an HTTP POST request.
            if isempty(obj.key)
                throw(blueftc.PIDConfigException('No key provided for value request.'));
            end

            % This is a two-step process: first set the value (this
            % method), then call the setter method (apply_values_request).
            keyName = sprintf('%s.%s', device, target);
            bodyMap = containers.Map();
            bodyMap('data') = containers.Map({keyName}, {struct('content', struct('value', value))});
            requestBody = jsonencode(bodyMap);

            requestPath = sprintf('https://%s:%d/values/?prettyprint=1&key=%s', obj.ip, obj.port, obj.key);

            if ~obj.emulate
                obj.log_message('DEBUG', sprintf('POST: %s - Body: %s', requestPath, requestBody));
                header = matlab.net.http.HeaderField('Content-Type', 'application/json');
                httpRequest = matlab.net.http.RequestMessage('POST', header, requestBody);
                uri = matlab.net.URI(requestPath);
                options = matlab.net.http.HTTPOptions('ConnectTimeout', 10, 'VerifyServerName', false);
                resp = send(httpRequest, uri, options);
                if double(resp.StatusCode) >= 400
                    error('blueftc:HTTPError', 'HTTP request failed with status %d', double(resp.StatusCode));
                end
                response = jsondecode(char(resp.Body.Data));
            else
                obj.log_message('DEBUG', sprintf('EMULATE, POST: %s - Body: %s', requestPath, requestBody));
                response = struct();
            end
        end

        function apply_values_request(obj, device)
            %APPLY_VALUES_REQUEST Apply all changed values for the target
            %   device to the device. Only necessary for some devices, such
            %   as the temperature controller, where the control unit does
            %   not have direct access to the device but needs to update
            %   configurations.
            if isempty(obj.key)
                throw(blueftc.PIDConfigException('No key provided for value request.'));
            end

            bodyMap = containers.Map();
            bodyMap('data') = containers.Map({sprintf('%s.write', device)}, {struct('content', struct('call', 1))});
            requestBody = jsonencode(bodyMap);

            requestPath = sprintf('https://%s:%d/values/?prettyprint=1&key=%s', obj.ip, obj.port, obj.key);

            if ~obj.emulate
                obj.log_message('DEBUG', sprintf('POST: %s - Body: %s', requestPath, requestBody));
                header = matlab.net.http.HeaderField('Content-Type', 'application/json');
                httpRequest = matlab.net.http.RequestMessage('POST', header, requestBody);
                uri = matlab.net.URI(requestPath);
                options = matlab.net.http.HTTPOptions('ConnectTimeout', 10, 'VerifyServerName', false);
                resp = send(httpRequest, uri, options);
                if double(resp.StatusCode) >= 400
                    error('blueftc:HTTPError', 'HTTP request failed with status %d', double(resp.StatusCode));
                end
            else
                obj.log_message('DEBUG', sprintf('EMULATE, POST: %s - Body: %s', requestPath, requestBody));
            end
        end
    end

    methods
        % ---- general functions ----

        function value = get_channel_data(obj, channel, target_value)
            %GET_CHANNEL_DATA Get the specified data from a given channel.
            %
            %   Parameters
            %   ----------
            %   channel : double
            %       The channel from which to retrieve the data.
            %   target_value : string
            %       The target value to retrieve from the channel.
            device_id = sprintf('mapper.heater_mappings_bftc.device.c%d', channel);
            obj.log_message('DEBUG', sprintf('Requesting value: %s  from channel %d', target_value, channel));
            data = obj.get_value_request(device_id, target_value);
            try
                value = obj.get_value_from_data_response(data, device_id, target_value);
            catch
                throw(blueftc.APIError(data));
            end
        end

        function temperature = get_channel_temperature(obj, channel)
            %GET_CHANNEL_TEMPERATURE Get the temperature of the given channel, in Kelvin.
            temperature = double(obj.get_channel_data(channel, 'temperature'));
        end

        function resistance = get_channel_resistance(obj, channel)
            %GET_CHANNEL_RESISTANCE Get the resistance of the given channel, in Ohm.
            resistance = double(obj.get_channel_data(channel, 'resistance'));
        end

        function temperature = get_mxc_temperature(obj)
            %GET_MXC_TEMPERATURE Get the temperature of the mixing chamber sensor, in Kelvin.
            if obj.has_mxc
                temperature = obj.get_channel_temperature(obj.mixing_chamber_channel_id);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function resistance = get_mxc_resistance(obj)
            %GET_MXC_RESISTANCE Get the resistance of the mixing chamber sensor, in Ohm.
            if obj.has_mxc
                resistance = obj.get_channel_resistance(obj.mixing_chamber_channel_id);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function value = get_mxc_heater_value(obj, target)
            %GET_MXC_HEATER_VALUE Get the target value of the mixing chamber heater.
            if obj.has_mxc
                data = obj.get_value_request(obj.mixing_chamber_heater, target);
                try
                    value = obj.get_value_from_data_response(data, obj.mixing_chamber_heater, target);
                catch
                    throw(blueftc.APIError(data));
                end
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function synced = check_heater_value_synced(obj, target)
            %CHECK_HEATER_VALUE_SYNCED Check if the value of the mixing chamber heater is synced.
            data = obj.get_value_request(obj.mixing_chamber_heater, target);
            try
                synced = logical(obj.handle_status_response( ...
                    obj.get_synchronization_status(data, obj.mixing_chamber_heater, target), target, true));
            catch
                throw(blueftc.APIError(data));
            end
        end

        function synced = set_mxc_heater_value(obj, target, value)
            %SET_MXC_HEATER_VALUE Set the value of the mixing chamber heater.
            if obj.has_mxc
                obj.log_message('INFO', sprintf('Mixing Chamber Heater: Setting %s to %s', target, string(value)));
                % Set the value.
                obj.set_value_request(obj.mixing_chamber_heater, target, value);
                % Apply the value (otherwise it doesn't get synced to the temperature controller).
                obj.log_message('DEBUG', 'Mixing Chamber Heater: Applying settings');
                obj.apply_values_request(obj.mixing_chamber_heater);
                synced = obj.check_heater_value_synced(target);
                obj.log_message('INFO', 'Mixing Chamber Heater: Settings applied and synced');
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function status = get_mxc_heater_status(obj)
            %GET_MXC_HEATER_STATUS Get the status of the mixing chamber heater.
            %   Returns true if the heater is active, false otherwise.
            if obj.has_mxc
                status = strcmp(string(obj.get_mxc_heater_value('active')), '1');
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function success = set_mxc_heater_status(obj, newStatus)
            %SET_MXC_HEATER_STATUS Set the status of the mixing chamber heater.
            %   Returns true if the status was set successfully, false otherwise.
            if obj.has_mxc
                if newStatus
                    newValue = '1';
                else
                    newValue = '0';
                end
                success = obj.set_mxc_heater_value('active', newValue);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function success = toggle_mxc_heater(obj, status)
            %TOGGLE_MXC_HEATER Toggle the heater switch.
            %
            %   Parameters
            %   ----------
            %   status : 'on' or 'off'
            if obj.has_mxc
                switch status
                    case 'on'
                        newValue = true;
                    case 'off'
                        newValue = false;
                    otherwise
                        throw(blueftc.PIDConfigException("Invalid status provided, must be 'on' or 'off'"));
                end
                success = obj.set_mxc_heater_status(newValue);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function power = get_mxc_heater_power(obj)
            %GET_MXC_HEATER_POWER Get the power of the mixing chamber heater, in microwatts.
            if obj.has_mxc
                power = double(obj.get_mxc_heater_value('power')) * 1000000.0;
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function success = set_mxc_heater_power(obj, power)
            %SET_MXC_HEATER_POWER Set the power of the mixing chamber heater, in microwatts.
            if obj.has_mxc
                % Sanity check, should be in microwatts.
                if power < 0 || power > 5000
                    throw(blueftc.PIDConfigException('Power should be in the range of 0 to 5000 microwatts'));
                end
                success = obj.set_mxc_heater_value('power', power / 1000000.0);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function setpoint = get_mxc_heater_setpoint(obj)
            %GET_MXC_HEATER_SETPOINT Get the setpoint of the mixing chamber heater.
            if obj.has_mxc
                setpoint = double(obj.get_mxc_heater_value('setpoint'));
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function success = set_mxc_heater_setpoint(obj, temperature, use_pid_calib)
            %SET_MXC_HEATER_SETPOINT Set the setpoint of the mixing chamber
            %   heater in milli Kelvin. If a calibration table was given in
            %   the constructor and use_pid_calib is true, the PID
            %   calibration closest to the desired setpoint will be applied
            %   before setting the setpoint.
            %
            %   Parameters
            %   ----------
            %   temperature : double
            %       The setpoint to set for the heater.
            %   use_pid_calib : logical, optional
            %       Toggle using the PID calibration table (default is true).
            arguments
                obj
                temperature double
                use_pid_calib (1,1) logical = true
            end

            if obj.has_mxc
                if use_pid_calib && obj.valid_pid_config
                    [~, closest] = min(abs(obj.pid_calib_setpoints - temperature));
                    obj.log_message('INFO', sprintf( ...
                        'Using PID calibration for setpoint %g mK, closest available calibration to %g mK.', ...
                        obj.pid_calib_setpoints(closest), temperature));
                    pidRow = num2cell(obj.pid_calib_pid(closest, :));
                    obj.set_mxc_heater_pid_config(pidRow{:});
                else
                    warning('blueftc:PIDCalibNotUsed', ...
                        'PID calibration not used, using current PID parameters stored on the device.');
                end

                if temperature >= 1e3
                    error('blueftc:SetpointTooHigh', ...
                        'Mixing chamber setpoint cannot be over 1K. You are trying to set %g mK.', temperature);
                end
                success = obj.set_mxc_heater_value('setpoint', temperature);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function mode = get_mxc_heater_mode(obj)
            %GET_MXC_HEATER_MODE Get the pid mode of the mixing chamber heater.
            %   Returns true if the pid mode is active, false otherwise.
            if obj.has_mxc
                mode = strcmp(string(obj.get_mxc_heater_value('pid_mode')), '1');
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function success = set_mxc_heater_mode(obj, toggle)
            %SET_MXC_HEATER_MODE Set the pid mode of the mixing chamber heater.
            if obj.has_mxc
                if toggle
                    newValue = '1';
                else
                    newValue = '0';
                end
                success = obj.set_mxc_heater_value('pid_mode', newValue);
            else
                error('blueftc:MxcNotConfigured', 'Mixing chamber channel ID not configured.');
            end
        end

        function pid = get_mxc_heater_pid_config(obj)
            %GET_MXC_HEATER_PID_CONFIG Get the pid parameters of the mixing
            %   chamber heater, returned as [P I D].
            letters = {'p', 'i', 'd'};
            pid = zeros(1, 3);
            for idx = 1:3
                pid(idx) = double(obj.get_mxc_heater_value(sprintf('pid_%s', letters{idx})));
            end
        end

        function success = set_mxc_heater_pid_config(obj, p, i, d)
            %SET_MXC_HEATER_PID_CONFIG Set the pid parameters of the mixing chamber heater.
            %
            %   Parameters
            %   ----------
            %   p, i, d : double, optional
            %       Proportional, integral and derivative PID parameters
            %       (default [] for each, meaning "leave unchanged").
            arguments
                obj
                p double = []
                i double = []
                d double = []
            end

            values = {p, i, d};
            letters = {'p', 'i', 'd'};
            success = true;
            for idx = 1:3
                v = values{idx};
                if ~isempty(v)
                    if ~obj.set_mxc_heater_value(sprintf('pid_%s', letters{idx}), v)
                        success = false;
                        return
                    end
                end
            end
        end

        % ---- pressure gauges ----

        function pressure = get_maxigauge_channel(obj, channel)
            %GET_MAXIGAUGE_CHANNEL Read the pressure value of a Pfeiffer
            %   Maxigauge unit, in mbar.
            %
            %   Parameters
            %   ----------
            %   channel : double
            %       Channel of the desired gauge.
            if obj.maxigauge_pressure
                target = sprintf('p%d', channel);
                data = obj.get_value_request('driver.maxigauge.pressures', target);
                obj.log_message('DEBUG', sprintf('Requesting pressure from gauge P%d', channel));
                try
                    pressure = double(obj.get_value_from_data_response(data, 'driver.maxigauge.pressures', target)) * 1e3;
                catch
                    throw(blueftc.APIError(data));
                end
            else
                error('blueftc:MaxigaugeNotActive', 'Activate maxigauge reading toggle to read pressure values.');
            end
        end
    end
end
