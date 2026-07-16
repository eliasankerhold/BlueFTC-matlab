function [API_KEY, IP_ADDRESS, PORT_NUMBER, MXC_ID, HEATER_ID, PID_CALIB_FILE] = credentials()
%CREDENTIALS Configuration values for connecting to the BlueFors control software.
%   MATLAB equivalent of the Python `examples/credentials.py` file. Since
%   MATLAB scripts don't export module-level variables the way Python
%   modules do, this is implemented as a function returning the values;
%   call it as:
%
%       [API_KEY, IP_ADDRESS, PORT_NUMBER, MXC_ID, HEATER_ID, PID_CALIB_FILE] = credentials();
%
%   Edit the values below to match your setup.

API_KEY = '123456789abcdefghijklmnopqrstuvwxyz';
IP_ADDRESS = '123.456.789.0';
PORT_NUMBER = 12345;
MXC_ID = 6;
HEATER_ID = 4;
PID_CALIB_FILE = 'examples/pid_calib.csv';

end
