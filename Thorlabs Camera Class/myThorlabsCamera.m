classdef myThorlabsCamera < handle
    % Matlab class to control Thorlabs Cameras DCx type using uc480DotNet.dll.
    %
    % This class was tested with a single Thorlabs DCC1545M camera and with ThorCam 64-bits.
    % Nonetheless, this class is designed to operate with other Thorlabs cameras of the same family.
    % Modifications could be needed to operate other models. Particular attention should be given to 
    % ADC resolution (ADCRESOLUTION) and colour mode (COLOURMODE) variables.
    %
    % This class was developed with to get images from the Thorlabs cameras using uc480DotNet.dll.
    %
    % Instructions:
    % cam = myThorlabsCamera() % connects with the first available camera.
    % cam = myThorlabsCamera(0) % connects with camera with Camera_ID number 0.
    % cam = myThorlabsCamera(4001234567) % connects with serial number 4001234567.
    %
    % Author: F.O.
    % Last Update: 2025-01-08
    
    
    properties (Constant, Hidden)
        % path to DLL files (edit as appropriate)
        DLLPATHDEFAULT_64BITS = 'C:\Program Files\Thorlabs\Scientific Imaging\DCx Camera Support\Develop\DotNet\';
        DLLPATHDEFAULT_32BITS = 'C:\Program Files (x86)\Thorlabs\Scientific Imaging\DCx Camera Support\Develop\DotNet\';
        DLLFILENAME = 'uc480DotNet.dll';
        
        % Error Message
        MSGERROR   = 'Error: ';
        MSGWARNING = 'Warning: ';
        CLASSNAME  = 'myThorlabsCamera.m > ';
    end
    
    properties (Hidden)
        % Camera Sensor Specs
        SENSORPIXELHORIZONTAL;              % Camera sensor horizontal/long size in number of pixels.
        SENSORPIXELVERTICAL;                % Camera sensor vertical/short size in number of pixels.
        PIXELSIZE;                          % Camera sensor pixel size in micros.
        
        % Camera Specs
        COLOURMODE;                         % Camera colour mode.
        ADCRESOLUTION;                      % Analogic-to-digital convert resolution in number of bits.
        MAXGREYLEVEL;                       % Maximum intensity value (2^bits - 1).
        
        % Camera Identification
        CAMERA_ID;                          % Camera identification number (0 to 255).
        CAMERA_SERIALNUMBER;                % Camera serial number.
        
        % Camera Pixel Clock, Frame rate & Exposure Time Lists
        LIST_PIXELCLOCK;                    % Array with all available pixelclock (from lowest to highest value), in MHz.
        LIST_EXPOSURETIMEMAX;               % Array with maximum Exposure Time for all available Pixel Clock values, in ms.
        LIST_EXPOSURETIMEMIN;               % Array with minimum Exposure Time for all available Pixel Clock values, in ms.
        LIST_FRAMERATEMAX;                  % Array with maximum Frame Rate for all available Pixel Clock values, in fps.
        LIST_FRAMERATEMIN;                  % Array with minimum Frame Rate for all available Pixel Clock values, in fps.
        LIST_SIZE;                          % Size of the five previous arrays.
        
        % Measurement Settings
        pixelClock;                         % Current Pixel Clock value, in MHz.
        frameRate;                          % Current Frame Rate value, in fps.
        exposureTime;                       % Current Exposure Time Value, in milliseconds.
        gainBoost;                          % Current Gain Boost (on - true; off - false).
        desiredPixelClock;                  % Desired Pixel Clock, final value can different to fit the Frame Rate.
        desiredFrameRate;                   % Desired Frame Rate, final value can different to fit the Exposure Time.
        desiredExposureTime;                % Desired Pixel Clock, final value can different due to camera restrictions.
       
        desiredGainBoost;                   % --------------
        
        listPosition;
        
        % Data
        DataFrame;
        CentreMassWidthPosition;
        CentreMassHeightPosition;
        
        % Other variables
        isconnected = false;                % Flag set if device connected
        initialized = false;                % initialization flag
        errorDetected = false;              % Flag for detected errors during execution.
    end
    
    properties 
       cameraObject;                        % Device camera object.
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % M E T H O D S - CONSTRUCTOR/DESCTRUCTOR
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        
        % =================================================================
        % FUNCTION myThorlabsCamera()
        % input:    'CameraID', value
        %           'SerialNumber', value
        % 
        function h = myThorlabsCamera(varargin) % Constructor
            
            functionName = 'myThorlabsCamera()';        % Function name string to use in messages.
            h.errorDetected = false;                    % Reset errorDetected flag.
            
            % Input Variables
            if nargin > 1
                
                for i = 1:nargin
                    switch lower(varargin{i})
                        case {'cameraid' 'camera_id' 'camera id' 'id'}
                            i = i+1;                    % Move counter to input value.
                            val = varargin{i};
                            if isnumeric(val)
                                
                            elseif ischar(val)
                                val = str2double(val);
                            else
                                h.errorDetected = true;
                                disp([h.MSGERROR h.CLASSNAME functionName ': invalid input.']);
                                return                 % End execution of function.
                            end
                            
                            if val >= 0 && val <= 255
                                h.CAMERA_ID = uint8(val);
                            else
                                h.errorDetected = true;
                                disp([h.MSGERROR h.CLASSNAME functionName ': invalid input.']);
                                return                 % End execution of function.
                            end
                            
                        case {'serialnumber' 'serial number' 'sn' 's/n'}
                            i = i+1;                    % Move counter to input value.
                            val = varargin{i};
                            if isnumeric(val)
                                
                            elseif ischar(val)
                                val = str2double(val);
                            else
                                h.errorDetected = true;
                                disp([h.MSGERROR h.CLASSNAME functionName ': invalid input.']);
                                return                 % End execution of function.
                            end
                            
                            if val > 0
                                h.CAMERA_SERIALNUMBER = uint64(val);
                            else
                                h.errorDetected = true;
                                disp([h.MSGERROR h.CLASSNAME functionName ': invalid input.']);
                                return                 % End execution of function.
                            end
                            
                        otherwise
                            h.CAMERA_ID = 0;            % Initialize first camera available (CameraID = 0).
                    end
                end
                
            else
                h.CAMERA_ID = 0;                        % Initialize first camera available (CameraID = 0).
            end
            
            % Create Camera Object and Initialize Camera
            if ~h.isconnected
                myThorlabsCamera.loaddlls;              % Load DLL.
                h.cameraObject = uc480.Camera;          % 'Create' camera object.
                
                if isempty(h.CAMERA_SERIALNUMBER)       % If camera serial number is unknown, uses defined or default camera ID number.
                    try
                        answer = h.cameraObject.Init(h.CAMERA_ID);      % Starts the driver and establishes the connection to the camera.
                        if ~contains(char(answer),'SUCCESS')
                            h.errorDetected = false;                   	% Flag an error was not detected.
                            h.isconnected = true;                       % Flag camera is connected.
                            disp([h.MSGERROR h.CLASSNAME functionName ': invalid camera initialization.']);
                            return;                                     % End execution of function.
                        end
                    catch
                        h.errorDetected = true;                         % Flag an error was detected.
                        h.isconnected = false;                          % Flag camera is not connected.
                        disp([h.MSGERROR h.CLASSNAME functionName ': invalid camera initialization.']);
                        return;                                         % End execution of function.
                    end
                else
                    for i=0:255
                        try
                            answer = h.cameraObject.Init(i);            % Starts the driver and establishes the connection to the camera.
                            if contains(char(answer),'SUCCESS')
                                [~,CameraInfo] = h.cameraObject.Information.GetImageInfo(); % Returns the data hard-coded in the EEPROM.
                                if h.CAMERA_SERIALNUMBER == uint64(str2double(CameraInfo.SerialNumber))
                                    h.CAMERA_ID = i;                    % Register camera id corresponding to camera serial number.
                                    h.errorDetected = false;            % Flag error was not detected.
                                    h.isconnected = true;            	% Flag camera is connected.
                                    break;                              % Break 'for' cycle.
                                end
                            end
                        catch
                            h.errorDetected = true;                     % Flag an error was detected.
                            h.isconnected = false;                      % Flag camera is not connected.
                            disp([h.MSGERROR h.CLASSNAME functionName ': invalid camera initialization.']);
                        end
                    end
                end

            else
                h.cameraObject.Exit;                    % Disables the camera handle and releases the data structures and
                                                        % memory areas taken up by the uc480 camera.
                h.cameraObject.Init(h.CAMERA_ID);       % Starts the driver and establishes the connection to the camera.
                                                        % Initialize first camera available (CameraID = 0).
                h.isconnected = true;            	    % Flag camera is connected.
            end
            
            % Get Camera Settings
            if ~h.errorDetected
                % Pixel Clock
                [~,PixelClockMinValue,PixelClockMaxValue,PixelClockStepValue] = h.cameraObject.Timing.PixelClock.GetRange;	% Returns the pixel clock range (minimum, maximum and increment)..
                h.LIST_PIXELCLOCK = PixelClockMinValue:PixelClockStepValue:PixelClockMaxValue;                	% Array with all available Pixel Clock values.

                h.LIST_SIZE = size(h.LIST_PIXELCLOCK,2);                                                    	% Array length.
                aux_RatioSettings = double(PixelClockMinValue)./double(h.LIST_PIXELCLOCK);                   	% Auxiliar array to determine all Frame Rates and Exposure Times per Pixel Clock.

                % Maximum and Minimum Frame rate per Pixel Clock
                h.cameraObject.Timing.PixelClock.Set(PixelClockMaxValue);                                       % Sets the frequency used to read out image data from the sensor (pixel clock frequency).
                [~,FrameRateMinValue,FrameRateMaxValue,~] = h.cameraObject.Timing.Framerate.GetFrameRateRange;  % Returns the frame rate range (minimum, maximum and increment).
                h.LIST_FRAMERATEMAX = flip(FrameRateMaxValue * aux_RatioSettings);                              % Array with maximum Frame Rate for all available Pixel Clock values.
                h.LIST_FRAMERATEMIN = flip(FrameRateMinValue * aux_RatioSettings);                              % Array with minimum Frame Rate for all available Pixel Clock values.

                % Maximum and Minimum Exposure Time per Pixel Clock
                h.cameraObject.Timing.PixelClock.Set(PixelClockMinValue);                                       % Sets the frequency used to read out image data from the sensor (pixel clock frequency).
                h.cameraObject.Timing.Framerate.Set(h.LIST_FRAMERATEMIN(1));                                    % Sets lowset frame rate.
                [~,ExposureTimeMinValue,ExposureTimeMaxValue,~] = h.cameraObject.Timing.Exposure.GetRange;      % Returns the exposure time range (minimum, maximum and increment).
                h.LIST_EXPOSURETIMEMAX = ExposureTimeMaxValue * aux_RatioSettings;                              % Array with maximum Exposure Time for all available Pixel Clock values.
                h.LIST_EXPOSURETIMEMIN = ExposureTimeMinValue * aux_RatioSettings;                              % Array with minimum Exposure Time for all available Pixel Clock values.

                % Sensor Information
                [~,SensorInfo] = h.cameraObject.Information.GetSensorInfo();            % Returns information about the sensor type used in the camera.
                h.SENSORPIXELHORIZONTAL = double(SensorInfo.MaxSize.Width);            	% Camera sensor horizontal/long size in number of pixels.
                h.SENSORPIXELVERTICAL   = double(SensorInfo.MaxSize.Height);          	% Camera sensor vertical/short size in number of pixels.
                h.PIXELSIZE             = double(SensorInfo.PixelSize)/100;             % Camera sensor pixel size in micros.

                SensorColorMode         = char(SensorInfo.SensorColorMode);             % Sensor colour mode: monochromatic or color.
                [~,bitsPerPixel]        = h.cameraObject.PixelFormat.GetBitsPerPixel;   % Returns the bits per pixel for the current color mode.
                
                if contains(SensorColorMode,'Monochrome')                       % If the sensor is monochromatir.
                    if bitsPerPixel <= 16
                        h.ADCRESOLUTION = bitsPerPixel;
                  	else
                        h.ADCRESOLUTION = bitsPerPixel/3;
                    end
                        
                    if h.ADCRESOLUTION == 8
                        h.ADCRESOLUTION = 8;                                % Camera ADC resolution.
                        h.COLOURMODE    = 'Mono8';                          % Camera color mode.
                        h.cameraObject.PixelFormat.Set(uc480.Defines.ColorMode.Mono8);
                    elseif h.ADCRESOLUTION > 8 && h.ADCRESOLUTION <= 12
                        h.ADCRESOLUTION = 12;                               % Camera ADC resolution.
                        h.COLOURMODE    = 'Mono12';                         % Camera color mode.
                        h.cameraObject.PixelFormat.Set(uc480.Defines.ColorMode.Mono12);
                    elseif h.ADCRESOLUTION > 12 && h.ADCRESOLUTION <= 16
                        h.ADCRESOLUTION = 16;                               % Camera ADC resolution.
                        h.COLOURMODE    = 'Mono16';                         % Camera color mode.
                        h.cameraObject.PixelFormat.Set(uc480.Defines.ColorMode.Mono16);
                    end
                else
                     h.ADCRESOLUTION  = bitsPerPixel/3;
                     [~,h.COLOURMODE] = h.cameraObject.PixelFormat.Get;   	% Returns current camera colour mode.
                end
                h.MAXGREYLEVEL          = 2^h.ADCRESOLUTION-1;              % Max grey level 8bits = 255.
                
                % Default Camera Settings
                h.listPosition = 1;
                h.pixelClock   = h.LIST_PIXELCLOCK(h.listPosition);         % Sets lowest pixel clock.
                h.frameRate    = h.LIST_FRAMERATEMIN(h.listPosition);       % Sets lowest frame rate for the lowest pixel clock.
                h.exposureTime = h.LIST_EXPOSURETIMEMIN(h.listPosition);    % Sets lowest exposure time for the lowest pixel clock.
                
                h.cameraObject.Timing.PixelClock.Set(h.pixelClock);
                h.cameraObject.Timing.Framerate.Set(h.frameRate);
                h.cameraObject.Timing.Exposure.Set(h.exposureTime);
            end
            
            % Disable Camera
%             if ~h.errorDetected
%                 h.cameraObject.Exit;                        % Disables the camera handle and releases the data structures and
%                                                             % memory areas taken up by the uc480 camera.
%             end
        end

        % =================================================================
        function delete(h) % Destructor 
            
            if ~isempty(h.cameraObject) && h.isconnected
                disconnect(h);
            end

        end
            
    end
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S (Sealed) - INTERFACE IMPLEMENTATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Sealed)

        % =================================================================
        % FUNCTION: CONNECT CAMERA
        function connect(h,varargin)
                      
            if ~h.isconnected                       % Execute only if it was not initilaed previously.
                h.cameraObject.Init(h.CAMERA_ID);       % Starts the driver and establishes the connection to the camera.
                                                        % Initialize first camera available (CameraID = 0).
                h.isconnected = true;
            else
                h.cameraObject.Exit;                    % Disables the camera handle and releases the data structures and
                                                        % memory areas taken up by the uc480 camera.
                h.cameraObject.Init(h.CAMERA_ID);       % Starts the driver and establishes the connection to the camera.
                                                        % Initialize first camera available (CameraID = 0).
                h.isconnected = true;
            end
        end
        
        % =================================================================
        % FUNCTION: DISCONNECT
        function disconnect(h) % Disconnect device     
            
            h.cameraObject.Exit();
            h.isconnected = false;      % Flag device not connected.
            
        end
        
        % =================================================================
        % FUNCTION: SET CAMERA SETTINGS
        % val = Exposure time value in milliseconds.
        function setExposureTime(h,val)
            
            functionName    = 'setExposureTime()';        % Function name string to use in messages.
            h.errorDetected = false;                        % Reset errorDetected flag.
            
            if isnumeric(val) && val > 0
                val = double(val);
            else
                val = 0;                  
            end
            
            % Initialize Camera
%             answer = h.cameraObject.Init(h.CAMERA_ID);      % Starts the driver and establishes the connection to the camera.
%             if contains(char(answer),'SUCCESS')
%                 h.errorDetected = false;                    % Flag error was not detected.
%                 h.isconnected = true;                       % Flag camera is connected.
%             else
%                 h.cameraObject.Exit;                        % Disables the camera handle and releases the data structures and
%                                                             % memory areas taken up by the uc480 camera.
%                 answer = h.cameraObject.Init(h.CAMERA_ID); 	% Starts the driver and establishes the connection to the camera.
%                 if contains(char(answer),'SUCCESS')         % Takes a seconds try to connect camera.
%                     h.errorDetected = false;                % Flag error was not detected.
%                     h.isconnected = true;                   % Flag camera is connected.
%                 else
%                     h.errorDetected = true;                 % Flag error was detected.
%                     h.isconnected = false;                	% Flag camera is not connected.
%                     disp([h.MSGERROR h.CLASSNAME functionName ': invalid camera initialization.']);
%                     return;
%                 end
%             end
            
            % Set Camera Exposure time
            if ~h.errorDetected
                % Get and Set Camera Exposure Time
                if val <= h.LIST_EXPOSURETIMEMIN(end)     % If desired exposure time is lower then the minimum available time.
                    disp([h.MSGWARNING h.CLASSNAME functionName ': exposure time set to minimum value available.']);
                    
                    h.listPosition = h.LIST_SIZE;
                    CurrentExposureTime = h.LIST_EXPOSURETIMEMAX(h.listPosition);
                    CurrentPixelClock = h.LIST_PIXELCLOCK(h.listPosition);
                    
                    h.cameraObject.Timing.PixelClock.Set(CurrentPixelClock);
                    
                    
                elseif val >= h.LIST_EXPOSURETIMEMAX(1)       % If exposure time is higher then the maximum available time.
                    disp([h.MSGWARNING h.CLASSNAME functionName ': exposure time set to maximum value available.']);
                    
                    h.listPosition = 1;
                   	CurrentExposureTime = h.LIST_EXPOSURETIMEMAX(h.listPosition);
                    CurrentPixelClock = h.LIST_PIXELCLOCK(h.listPosition);
                    
                    h.cameraObject.Timing.PixelClock.Set(CurrentPixelClock);
                    
                elseif val >= h.LIST_EXPOSURETIMEMIN(h.listPosition) && val <= h.LIST_EXPOSURETIMEMAX(h.listPosition)
                    CurrentExposureTime = val;
                    
                else        % If it is in the limits of the camera but out of the current Pixel Clock or Frame Rate.
                    disp([h.MSGWARNING h.CLASSNAME functionName ': exposure time is incompatible with current Pixel Clock / Frame Rate. Desired Exposure Time has priority.']);
                    
                    lowerestAcceptablePixelClock = false;
                    for i = 1:h.LIST_SIZE
                        if val >= h.LIST_EXPOSURETIMEMIN(i)
                            CurrentExposureTime = val;
                            
                            % If is the lowest acceptable pixel clock value
                            if ~lowerestAcceptablePixelClock
                                lowerestAcceptablePixelClock = true;
                                h.listPosition = i;
                            end
                            
                            
                            % If 
                            if val > h.LIST_EXPOSURETIMEMAX(i)
                                break;
                            end
                        end
                    end
                    h.cameraObject.Timing.PixelClock.Set(h.listPosition);
                    
                end
                h.cameraObject.Timing.Exposure.Set(CurrentExposureTime);
            end
            
            [~,h.exposureTime] = h.cameraObject.Timing.Exposure.Get();
            [~,h.pixelClock] = h.cameraObject.Timing.PixelClock.Get();
            
        end
        
        % =================================================================
        % FUNCTION: SET CAMERA SETTINGS
        function setCameraSettings(h,varargin)
            
            functionName    = 'setCameraSettings()';      % Function name string to use in messages.
            h.errorDetected = false;                      % Reset errorDetected flag.
            
            h.desiredPixelClock   = uint8.empty;
            h.desiredFrameRate    = double.empty;
            h.desiredExposureTime = double.empty;
            h.desiredGainBoost    = false;
            
            % 
            if nargin > 1
                for i = 1:nargin-1
                    switch lower(varargin{i})
                        case {'pixelclock' 'pixel clock'}
                            i = i+1;
                            val = varargin{i};
                            
                            if isnumeric(val) && val > 0
                                h.desiredPixelClock = uint8(val);
                            else
                                h.desiredPixelClock = 0;
                            end
                            
                        case {'framerate' 'frame rate'}
                            i = i+1;
                            val = varargin{i};
                            
                            if isnumeric(val) && val > 0
                                h.desiredFrameRate = double(val);
                            else
                                h.desiredFrameRate = 0;
                            end
                            
                        case {'exposuretime' 'exposure time' 'time'}
                            i = i+1;
                            val = varargin{i};
                            
                            if isnumeric(val) && val > 0
                                h.desiredExposureTime = double(val);
                            else
                                h.desiredExposureTime = 0;
                            end
                            
                        case {'gainboost' 'gain boost'}
                            i = i+1;
                            val = varargin{i};

                            if val == true && contains(val,'true')
                                h.desiredExposureTime = true;
                            else
                                h.desiredExposureTime = false;
                            end
                            
                    end
                end
            end
            
            % Initialize Camera
            answer = h.cameraObject.Init(h.CAMERA_ID);      % Starts the driver and establishes the connection to the camera.
            if contains(char(answer),'SUCCESS')
                h.errorDetected = false;                    % Flag error was not detected.
                h.isconnected = true;                       % Flag camera is connected.
            else
                h.cameraObject.Exit;                        % Disables the camera handle and releases the data structures and
                                                            % memory areas taken up by the uc480 camera.
                answer = h.cameraObject.Init(h.CAMERA_ID); 	% Starts the driver and establishes the connection to the camera.
                if contains(char(answer),'SUCCESS')         % Takes a seconds try to connect camera.
                    h.errorDetected = false;                % Flag error was not detected.
                    h.isconnected = true;                   % Flag camera is connected.
                else
                    h.errorDetected = true;                 % Flag error was detected.
                    h.isconnected = false;                	% Flag camera is not connected.
                    disp([h.MSGERROR h.CLASSNAME functionName ': invalid camera initialization.']);
                    return;
                end
            end
            
            % Set Camera Settings By Order of Importance
            if ~h.errorDetected
                % Set Camera PixelClock
                if h.desiredPixelClock < h.LIST_PIXELCLOCK(1)
                    Current_PixelClock = h.LIST_PIXELCLOCK(1);
                elseif h.desiredPixelClock > h.LIST_PIXELCLOCK(end)
                    Current_PixelClock = h.LIST_PIXELCLOCK(end);
                else
                    Current_PixelClock = h.desiredPixelClock;
                end

                h.cameraObject.Timing.PixelClock.Set(Current_PixelClock);
                h.pixelClock = Current_PixelClock;
                h.listPosition = find(h.LIST_PIXELCLOCK == h.pixelClock); % Obtain array position for pixelclock list.
                
              	% Set Camera FrameRate
                if h.desiredFrameRate == 0
                    Current_FrameRate = h.LIST_FRAMERATEMIN(h.listPosition);
                    
                elseif h.desiredFrameRate < h.LIST_FRAMERATEMIN(1)
                    Current_PixelClock = h.LIST_PIXELCLOCK(1);
                    h.cameraObject.Timing.PixelClock.Set(Current_PixelClock);
                    h.listPosition = 1;
                    Current_FrameRate = h.LIST_FRAMERATEMIN(1);
                    
                elseif h.desiredFrameRate > h.LIST_FRAMERATEMAX(end)
                    Current_PixelClock = h.LIST_PIXELCLOCK(end);
                    h.cameraObject.Timing.PixelClock.Set(Current_PixelClock);
                    h.listPosition = h.LIST_SIZE;
                    Current_FrameRate = h.LIST_FRAMERATEMAX(end);
                    
                elseif h.desiredFrameRate >= h.LIST_FRAMERATEMIN(h.listPosition) && h.desiredFrameRate <= h.LIST_FRAMERATEMAX(h.listPosition)
                    Current_FrameRate = h.desiredFrameRate;
                    
                else
                    for i = 1:h.LIST_SIZE
                        if h.desiredFrameRate >= h.LIST_FRAMERATEMAX(i)
                            break;
                        end
                    end
                    h.listPosition = i;
                    disp([h.MSGWARNING h.CLASSNAME functionName ': framerate incompatible with current Pixel Clock. Desired framerate has priority.']);
                    Current_FrameRate = h.desiredFrameRate;                  % If framerate is out of range, camera will convert it to closest acceptble value.
                end
                h.cameraObject.Timing.Framerate.Set(Current_FrameRate);
                h.farmeRate = Current_FrameRate;
                h.listPosition = find(h.LIST_PIXELCLOCK == h.pixelClock); % Obtain array position for pixelclock list.
                
                % Get and Set Camera Exposure Time
                if h.desiredExposureTime == 0
                    CurrentExposureTime = h.LIST_EXPOSURETIMEMIN(h.listPosition);
                    
                elseif h.desiredExposureTime <= h.LIST_EXPOSURETIMEMIN(end)     % If exposure time is lower then the minimum available time.
                    disp([h.MSGWARNING h.CLASSNAME functionName ': exposure time changed to minimum available.']);
                    
                    CurrentExposureTime = h.LIST_EXPOSURETIMEMIN(end);
                    h.cameraObject.Timing.PixelClock.Set(Current_PixelClock);
                    h.listPosition = h.LIST_SIZE;
                    
                    % framerate part
                    if h.desiredFrameRate == 0
                        Current_FrameRate = h.LIST_FRAMERATEMIN(h.listPosition);
                    elseif h.desiredFrameRate < h.LIST_FRAMERATEMIN(h.listPosition)
                        Current_FrameRate = h.LIST_FRAMERATEMIN(h.listPosition);
                    elseif h.desiredFrameRate > h.LIST_FRAMERATEMAX(h.listPosition)
                        Current_FrameRate = h.LIST_FRAMERATEMAX(h.listPosition);
                    else
                        Current_FrameRate = h.desiredFrameRate;
                    end
                    h.cameraObject.Timing.Framerate.Set(Current_FrameRate);     % Set camera framerate.
                    h.farmeRate = Current_FrameRate;
                    
                elseif h.desiredExposureTime >= h.LIST_EXPOSURETIMEMAX(1)       % If exposure time is higher then the maximum available time.
                    disp([h.MSGWARNING h.CLASSNAME functionName ': exposure time changed to maximum available.']);
                    
                   	CurrentExposureTime = h.LIST_EXPOSURETIMEMIN(end);
                    h.cameraObject.Timing.PixelClock.Set(Current_PixelClock);
                    h.listPosition = h.LIST_SIZE;
                    
                    % framerate part
                    if h.desiredFrameRate == 0
                        Current_FrameRate = h.LIST_FRAMERATEMIN(h.listPosition);
                    elseif h.desiredFrameRate < h.LIST_FRAMERATEMIN(h.listPosition)
                        Current_FrameRate = h.LIST_FRAMERATEMIN(h.listPosition);
                    elseif h.desiredFrameRate > h.LIST_FRAMERATEMAX(h.listPosition)
                        Current_FrameRate = h.LIST_FRAMERATEMAX(h.listPosition);
                    else
                        Current_FrameRate = h.desiredFrameRate;
                    end
                    h.cameraObject.Timing.Framerate.Set(Current_FrameRate);
                    h.farmeRate = Current_FrameRate;
                    
                elseif h.desiredExposureTime >= h.LIST_EXPOSURETIMEMIN(h.listPosition) && h.desiredExposureTime <= h.LIST_EXPOSURETIMEMAX(h.listPosition)
                    CurrentExposureTime = h.desiredExposureTime;
                    
                else        % If it is in the limits of the camera but out of the current Pixel Clock or Frame Rate.
                    disp([h.MSGWARNING h.CLASSNAME functionName ': exposure time is incompatible with current Pixel Clock and/or Frame Rate. Desired Exposure Time has priority.']);
                    
                    lowerestAcceptablePixelClock = false;
                    for i = 1:h.LIST_SIZE
                        if h.desiredExposureTime >= h.LIST_EXPOSURETIMEMIN(i)
                            CurrentExposureTime = h.desiredExposureTime;
                            
                            % If is the lowest acceptable pixeal clock value
                            if ~lowerestAcceptablePixelClock
                                lowerestAcceptablePixelClock = true;
                                h.listPosition = i;
                            end
                            
                            % Check if can accomudade the desired frame rate
                            if h.desiredFrameRate == 0                          % If minimum frame rate is desired.
                                h.desiredFrameRate = h.LIST_FRAMERATEMIN(i);    % Minimum frame rate for current Pixel Clock.
                                h.listPosition = i;
                                break;
                            elseif h.desiredFrameRate >= h.LIST_FRAMERATEMIN(i) && h.desiredFrameRate <= h.LIST_FRAMERATEMAX(i)
                                h.listPosition = i;
                                break;
                            else
                                if i > 1
                                    if (h.desiredFrameRate - h.LIST_FRAMERATEMAX(i)) > (h.desiredFrameRate - h.LIST_FRAMERATEMAX(i-1))
                                        h.listPosition = i;
                                    else
                                        break;
                                    end
                                end
                            end
                            
                            % If 
                            if h.desiredExposureTime > h.LIST_EXPOSURETIMEMAX(i)
                                break;
                            end
                        end
                    end
                    h.cameraObject.Timing.PixelClock.Set(h.listPosition);
                    h.cameraObject.Timing.Framerate.Set(h.desiredFrameRate);
                    
                end
                h.cameraObject.Exposure.Set(CurrentExposureTime);
                
            end
                
            % Disable Camera
            if ~h.errorDetected
                h.cameraObject.Exit;                    % Disables the camera handle and releases the data structures and
                                                        % memory areas taken up by the uc480 camera.
            end
            
        end
        
        
        % =================================================================
        % FUNCTION: GET FRAME
        function [status,Data] = getFrame(h)
            
            functionName    = 'getFrame()';        % Function name string to use in messages.
            h.errorDetected = false;                        % Reset errorDetected flag.
            
            % Set Colour Mode - It has to be set here because after uc480.Camera.Exit() this setting will be reset.
            switch h.COLOURMODE
                case 'Mono8'
                    h.cameraObject.PixelFormat.Set(uc480.Defines.ColorMode.Mono8);
                case 'Mono12'
                    h.cameraObject.PixelFormat.Set(uc480.Defines.ColorMode.Mono12);
                case 'Mono16'
                    h.cameraObject.PixelFormat.Set(uc480.Defines.ColorMode.Mono16);
                otherwise
            end
            
            % Set display mode to bitmap (DiB)
            h.cameraObject.Display.Mode.Set(uc480.Defines.DisplayMode.DiB);

            % Set trigger mode to software (single image acquisition)
            h.cameraObject.Trigger.Set(uc480.Defines.TriggerMode.Software);
            
            % Allocate image memory
            [~, MemId] = h.cameraObject.Memory.Allocate(true);
            
            % Obtain image information
            [~, Width, Height, Bits, ~] = h.cameraObject.Memory.Inquire(MemId);
            
            % Image Aquisition
            h.cameraObject.Acquisition.Freeze(uc480.Defines.DeviceParameter.Wait);     % Acquire image
            [~, tmp] = h.cameraObject.Memory.CopyToArray(MemId);                       % Copy image from memory

            % Reshape image
            switch Bits
                case 8
                    Data = reshape(uint8(tmp), [Bits/8, Width, Height]);
                    Data = squeeze(Data(1,:,:))';
                case 12
                    Data = reshape(uint16(tmp), [Bits/12, Width, Height]);
                    Data = squeeze(Data(1,:,:))';
                case 16
                    Data = reshape(uint16(tmp), [Bits/16, Width, Height]);
                    Data = squeeze(Data(1,:,:))';
                otherwise
                    Data = reshape(uint8(tmp), [Bits/8, Width, Height]);
                    Data = permute(Data, [3, 2, 1]);
            end
            h.DataFrame = Data;

            % Check if Shot Has Information
            if sum(Data(:)) ~= 0
                status = 'success';
            else
                status = 'failed';
            end
            
        end
        
        
    end
    
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% M E T H O D S  (STATIC) - load DLLs, get a list of devices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods (Static) % methods (Static)

        function loaddlls() % Load DLLs
            
            if exist(myThorlabsCamera.DLLPATHDEFAULT_64BITS,'dir') == 7   	% Default ThorCam uc480 dll path, 64-bits version, Microsoft Windows 64-bits. 
                path = myThorlabsCamera.DLLPATHDEFAULT_64BITS ;
            elseif exist(myThorlabsCamera.DLLPATHDEFAULT_32BITS,'dir') == 7 	% Default ThroCam uc480 dll path, 32-bits version, Microsoft Windows 32-bits.
                path = myThorlabsCamera.DLLPATHDEFAULT_32BITS ;
            else                                            % Current matlab path in use.
                path = '';
            end
            
            filepath = [path,myThorlabsCamera.DLLFILENAME];     % Build path to DLL file.
            if exist(filepath,'file')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly(filepath);
                catch % DLLs did not load
                    msg = "Unable to load .NET assemblies";
                    title = 'Error';
                    icon = 'error';
                    msgbox(msg,title,icon);
                end
            else
                msg = ["Thorlabs " DLLFILENAME " was not found."];
                title = 'Error';
                icon = 'error';
                msgbox(msg,title,icon);
            end    
        end 

    end 
    
end