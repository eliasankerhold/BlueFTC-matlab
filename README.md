# BlueFTC (MATLAB)

A MATLAB port of [BlueFTC](https://github.com/eliasankerhold/BlueFTC), a simple
Python interface for temperature controllers of Bluefors cryostats.

This package mirrors the structure, class/method names, and usage of the
original Python package as closely as MATLAB allows. It uses HTTP GET/POST
commands within a local network to remotely read and write to a temperature
controller using the Bluefors control software's API — exactly as the
Python original does.

## Table of Contents

1. [About The Project](#about-the-project)
2. [Getting Started](#getting-started)
   - [Installation](#installation)
   - [Quick Start To Read Mixing Chamber Temperature](#quick-start-to-read-mixing-chamber-temperature)
   - [Full Usage](#full-usage)
3. [Differences From The Python Package](#differences-from-the-python-package)
4. [License](#license)

## About The Project

The control software for Bluefors cryostats and their temperature controller
does not come with a native MATLAB interface either. This package uses
MATLAB's built-in `matlab.net.http` interface to talk to the Bluefors control
software's local HTTP API, so — like the Python original — it has **no
external dependencies** beyond MATLAB itself (no toolboxes required).

## Getting Started

As with the Python package, the Bluefors control software API can only be
accessed through a local network. The measurement computer needs to be part
of the same local network as the machine running the Bluefors control
software. You'll also need the local IP address, port number, and an API key
(created and configured in the Bluefors control software).

### Installation

Copy the `+blueftc` folder into a directory that is on your MATLAB path (or
add its parent directory to the path with `addpath`). Because it is a
package folder (`+blueftc`), its contents are accessed as `blueftc.<Name>`,
e.g. `blueftc.BlueFTController`.

```matlab
addpath('/path/to/BlueFTC-matlab');   % parent directory containing +blueftc
```

Requires MATLAB R2021a or later (for `name=value` call syntax on the
constructor; see below). No toolboxes are required — only base MATLAB.

### Quick Start To Read Mixing Chamber Temperature

```matlab
% define required configuration
API_KEY = '123456789abcdefghijklmnopqrstuvwxyz';
IP_ADDRESS = '123.456.789.0';
PORT_NUMBER = 12345;
MXC_ID = 6;
HEATER_ID = 4;

% create controller object
controller = blueftc.BlueFTController(ip=IP_ADDRESS, port=PORT_NUMBER, key=API_KEY, ...
    mixing_chamber_channel_id=MXC_ID, mixing_chamber_heater_id=HEATER_ID);

% read mixing chamber temperature in Kelvin
mxc_temp = controller.get_mxc_temperature();
```

Note that MATLAB's `name=value` argument syntax (available since R2021a)
mirrors Python's keyword arguments almost exactly. If you're on an older
MATLAB release, use the classic `'name', value` pair syntax instead — both
work identically since the constructor is implemented with an `arguments`
block.

### Full Usage

Once on the path, the package can be integrated into measurement scripts.
For convenience, store your IP address, port number and API key in a
separate function (see `examples/credentials.m`) and call it at the
beginning of your measurement script, exactly as the Python original
recommends storing them in a `credentials.py` file.

```matlab
[API_KEY, IP_ADDRESS, PORT_NUMBER, MXC_ID, HEATER_ID, PID_CALIB_FILE] = credentials();

% create controller object
controller = blueftc.BlueFTController(ip=IP_ADDRESS, port=PORT_NUMBER, key=API_KEY, ...
    mixing_chamber_channel_id=MXC_ID, mixing_chamber_heater_id=HEATER_ID);

% -------- READ OPERATIONS --------
% The following commands only require an API key with read permissions and
% are always safe to execute.

% read mixing chamber temperature, in Kelvin
mxc_temp = controller.get_mxc_temperature();

% read temperature of arbitrary channel by supplying the corresponding channel ID, in Kelvin
temp = controller.get_channel_temperature(1);

% read resistance of mixing chamber sensor or arbitrary channel, in Ohm
mxc_res = controller.get_mxc_resistance();
res = controller.get_channel_resistance(1);

% check if the mixing chamber heater is turned on or off
mxc_heater_status = controller.get_mxc_heater_status();

% read power of mixing chamber heater, in microwatts
mxc_power = controller.get_mxc_heater_power();

% check if the mixing chamber heater is operating in manual (0) or PID (1) mode
mxc_mode = controller.get_mxc_heater_mode();

% read the temperature setpoint of the mixing chamber heater PID control, in Kelvin
mxc_setpoint = controller.get_mxc_heater_setpoint();

% -------- WRITE OPERATIONS --------
% These commands require an API key with read and write permission and can
% potentially cause substantial damage to the hardware. Only execute with
% caution and absolute certainty of what is going to happen!
%
% All write commands return true if executed successfully, otherwise false.

% toggle mixing chamber heater
status = controller.toggle_mxc_heater('off');

% set power of the mixing chamber heater, in microwatts
status = controller.set_mxc_heater_power(100);

% set the set point of the mixing chamber PID control, in millikelvin
status = controller.set_mxc_heater_setpoint(30);

% turn the mixing chamber PID control on (true) or off (false)
status = controller.set_mxc_heater_mode(true);
```

#### Using a PID calibration table

Exactly as in the Python original, providing a `pid_calib_path` when
constructing the object enables automatic PID parameter adjustment when
changing the setpoint:

```matlab
controller = blueftc.BlueFTController(ip=IP_ADDRESS, port=PORT_NUMBER, key=API_KEY, ...
    mixing_chamber_channel_id=MXC_ID, mixing_chamber_heater_id=HEATER_ID, ...
    pid_calib_path='path/to/my/calibration_table.csv');
```

The table must have one header row and four columns: setpoint (in milli
Kelvin), P, I, D. `set_mxc_heater_setpoint(temperature)` will find the
calibration row closest to `temperature` and apply it before setting the
setpoint. Pass `use_pid_calib=false` (i.e.
`set_mxc_heater_setpoint(temperature, false)`) to suppress this even if a
table is loaded.

#### Reading Pressure Gauges

Pass `activate_maxigauge_reading=true` when constructing the object to
enable `get_maxigauge_channel(channel)`, which reads the pressure (in mbar)
of a Pfeiffer Vacuum Maxigauge channel.

## Differences From The Python Package

MATLAB and Python differ enough that a handful of small adaptations were
necessary. These are the only intentional deviations from a literal,
line-by-line translation:

| Python | MATLAB | Reason |
|---|---|---|
| `pip install .` package | `+blueftc` package folder on the MATLAB path | MATLAB's namespace mechanism |
| `_setup_logging`, `_load_pid_config`, `_handle_status_response`, `_get_synchronization_status`, `_get_value_request`, `_get_value_from_data_response`, `_set_value_request`, `_apply_values_request` | `setup_logging`, `load_pid_config`, `handle_status_response`, `get_synchronization_status`, `get_value_request`, `get_value_from_data_response`, `set_value_request`, `apply_values_request` (all in a `methods (Access = private)` block) | MATLAB identifiers cannot start with `_`; `Access = private` is used instead to keep them non-public |
| `self.logger` (Python `logging.Logger`, `TimedRotatingFileHandler`) | Private `log_message`/`rotate_log_if_needed` methods writing to `bluefors.log` | MATLAB has no built-in logging framework equivalent; weekly (Sunday) rotation with a 12-file backlog is approximated manually |
| `requests` GET/POST with `verify=False` | `matlab.net.http.RequestMessage`/`HTTPOptions('VerifyServerName', false)` | MATLAB's built-in HTTP client; `VerifyServerName=false` is the equivalent of disabling verification for the self-signed certificate |
| Python `dict` keys containing dots (e.g. `"driver.bftc...heater_4.setpoint"`) | `containers.Map` (encoding) and `matlab.lang.makeValidName` (decoding lookups) | MATLAB struct field names cannot contain dots; `jsonencode` on a `containers.Map` preserves arbitrary key strings, and `jsondecode` sanitizes such keys the same way `matlab.lang.makeValidName` does |
| Keyword arguments, e.g. `BlueFTController(ip=..., port=...)` | MATLAB `arguments` block + `name=value` call syntax (R2021a+) | Closest built-in MATLAB equivalent to Python kwargs with defaults |
| `set` parameter name in `_handle_status_response` | renamed to `set_flag` | `set` is a reserved/ambiguous identifier in MATLAB |
| `raise Exception(...)` for generic errors | `error('blueftc:<id>', ...)` | MATLAB's standard error-raising mechanism |
| Custom `PIDConfigException`/`APIError` (subclass `Exception`) | `classdef PIDConfigException < MException`, `classdef APIError < MException` | MATLAB's built-in exception base class |

All method names, parameter names, defaults, return value conventions
(`true`/`false` for write operations), units, and overall control flow are
kept identical to the Python original.

## License

Distributed under the GNU GPLv3 License, matching the original Python
package's license (see `LICENSE.txt` in the original
[BlueFTC repository](https://github.com/eliasankerhold/BlueFTC)).

## Credit

This is a MATLAB port of the original Python package **BlueFTC** by
Elias Ankerhold and Thomas Pfau (Aalto University):
https://github.com/eliasankerhold/BlueFTC
