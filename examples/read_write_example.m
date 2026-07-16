%READ_EXAMPLE Minimal working example of read commands.
%   MATLAB equivalent of the Python `examples/read_example.py` file.

addpath(genpath('C:\\Path\\to\\your\\directory\\BlueFTC-matlab'))

[API_KEY, IP_ADDRESS, PORT_NUMBER, MXC_ID, HEATER_ID, PID_CALIB_FILE] = credentials_secure();

% NOTE: Unlike Python's `requests` package, MATLAB's HTTP interface
% (matlab.net.http) does not print console warnings about disabled
% certificate verification, so there is no equivalent step needed here for
% the "InsecureRequestWarning" that the Python example disables.

controller = blueftc.BlueFTController(ip=IP_ADDRESS, port=PORT_NUMBER, key=API_KEY, ...
    mixing_chamber_channel_id=MXC_ID, mixing_chamber_heater_id=HEATER_ID, ...
    pid_calib_path=PID_CALIB_FILE, emulate=false, debug=false, controller_type='lakeshore');

active_channels = [1, 2, 5, 6];

for ch = active_channels
    fprintf('Channel %d temp: %g Kelvin\n', ch, controller.get_channel_temperature(ch));
    fprintf('Channel %d resistance: %g Ohm\n', ch, controller.get_channel_resistance(ch));
end

fprintf('MXC heater status: %d\n', controller.get_mxc_heater_status());
fprintf('MXC heater power: %g uW\n', controller.get_mxc_heater_power());
fprintf('MXC heater PID: %d\n', controller.get_mxc_heater_mode());
fprintf('MXC heater setpoint: %g K\n', controller.get_mxc_heater_setpoint());
fprintf('MXC heater PID config: %s\n', mat2str(controller.get_mxc_heater_pid_config()));

controller.set_mxc_heater_setpoint(0);
controller.set_mxc_heater_status(1);