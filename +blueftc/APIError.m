classdef APIError < MException
    %APIERROR Exception raised when the BlueFors control software API returns an error.
    %   MATLAB equivalent of the Python class `APIError` defined in
    %   BlueforsController.py. Constructed from the decoded JSON error
    %   response returned by the control software's HTTP API.
    %
    %   This is not exactly how the error is described in the API
    %   documentation. Let's see if it works for you (kept faithful to the
    %   original Python implementation's comment).
    %
    %   Properties
    %   ----------
    %   error_messages : cell array of char
    %       Formatted "Code: ..., Reason: ..." strings, one per error detail.
    %   query : the query that caused the error, as returned by the API.
    %   query_data : the query data that caused the error, as returned by the API.
    %   data : the data associated with the error, as returned by the API.

    properties
        error_messages
        query
        query_data
        data
    end

    methods
        function obj = APIError(jsonData)
            %APIERROR Construct the exception from a decoded JSON error struct.
            %
            %   Parameters
            %   ----------
            %   jsonData : struct
            %       The struct obtained from jsondecode() of the API's JSON
            %       error response. Must contain a "error" field.
            errorField = jsonData.error;

            % This assumes we got a details array (mirrors the Python
            % "details" in jsonData["error"] check).
            if isfield(errorField, 'details')
                details = errorField.details;
            else
                details = errorField;
            end

            % Normalize "details" to a cell array of scalar structs so we can
            % iterate over it regardless of whether jsondecode produced a
            % struct array or a single struct.
            if iscell(details)
                detailsList = details;
            elseif isstruct(details) && numel(details) > 1
                detailsList = num2cell(details);
            else
                detailsList = {details};
            end

            errors = {};
            for k = 1:numel(detailsList)
                entry = detailsList{k};
                errors{end+1} = sprintf('Code: %s, Reason: %s', ... %#ok<AGROW>
                    string(entry.code), string(entry.name));
            end

            message = sprintf('%s: %s, due to the following errors%s', ...
                errorField.name, errorField.description, strjoin(errors, ''));

            obj = obj@MException('blueftc:APIError', '%s', message);
            obj.error_messages = errors;
            obj.query = errorField.query;
            obj.query_data = errorField.query_data;
            obj.data = errorField.data;
        end
    end
end
