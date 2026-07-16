classdef PIDConfigException < MException
    %PIDCONFIGEXCEPTION Exception raised for invalid PID / value request configuration.
    %   MATLAB equivalent of the Python class `PIDConfigException` defined in
    %   BlueforsController.py. It is raised, for example, when no API key has
    %   been provided for a value request, or when an invalid heater status
    %   string is supplied.
    %
    %   Usage
    %   -----
    %       throw(blueftc.PIDConfigException('No key provided for value request.'))

    methods
        function obj = PIDConfigException(msg)
            %PIDCONFIGEXCEPTION Construct the exception with a message string.
            %
            %   Parameters
            %   ----------
            %   msg : char or string
            %       The message describing the error.
            obj = obj@MException('blueftc:PIDConfigException', '%s', char(msg));
        end
    end
end
