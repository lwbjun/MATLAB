
classdef kSerial < handle

properties (SetAccess = public)

end

properties (SetAccess = private)
    serial;
    comPort = '';
    baudRate = 115200;
    inputBufferSize = 8192;

    ks     = struct;
    tick   = struct;
    record = struct;
    packet = struct;
end

methods

    % ---- constructor
    % s = kSerial()                               ->  port = 'auto', baudRate = 115200, no delete instrfindall
    % s = kSerial(baudRate)                       ->  port = 'auto', set baudRate, no delete instrfindall
    % s = kSerial(port, baudRate)                 ->  set port, set baudRate, no delete instrfindall
    % s = kSerial(baudRate, 'clear')              ->  port = 'auto', delete instrfindall
    % s = kSerial(port, baudRate, 'clear')        ->  set port, set baudRate, delete instrfindall
    %                                             ->  port = 'COMx', 'auto', 'select'
    function s = kSerial( varargin )
        switch nargin
            case 0
                port = 'auto';
                s.baudRate = 115200;
            case 1
                port = 'auto';
                s.baudRate = varargin{1};
            case 2
                if ischar(varargin{1})
                    port = varargin{1};
                    s.baudRate = varargin{2};
                else
                    port = 'auto';
                    s.baudRate = varargin{1};
                    if strcmp(varargin{2}, 'clear')
                        delete(instrfindall);
                    end
                end
            case 3
                port = varargin{1};
                s.baudRate = varargin{2};
                if strcmp(varargin{3}, 'clear')
                    delete(instrfindall);
                end
            otherwise
                error('input error!!');
        end
        info = instrhwinfo('serial');
        comPortList = info.AvailableSerialPorts;

        if strcmp(port, 'auto')
            s.comPort = char(comPortList(1));
        elseif strcmp(port, 'select')
            fprintf('-- serial port : ');
            for i = 1 : size(char(comPortList), 1)
                fprintf(['\t[%d] ', char(comPortList(i))], i);
            end
            comPort = input('\n');
            if isempty(comPort) || (comPort > size(char(comPortList), 1))
                s.comPort = comPortList(1);
            else
                s.comPort = comPortList(comPort);
            end
        elseif strncmp(port, 'COM', 3)
            s.comPort = port;
        else
            error('com port error!!');
        end

        s.serial = serial(s.comPort, 'BaudRate', s.baudRate, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none', 'FlowControl', 'none');
        s.serial.ReadAsyncMode = 'continuous';
        s.serial.InputBufferSize = s.inputBufferSize;

        fprintf(['com port : ', s.comPort, '\n']);

        s.packet.maxLens = 1;

        s.packet.recvThreshold = 0;
        s.packet.recvBuffer    = [];
        s.packet.recvBuffSize  = 0;

        s.record.info       = [];
        s.record.data       = [];
        s.record.bufferSize = 0;
        s.record.count      = 0;
        s.record.totalBytes = 0;

        s.ks.info  = [];
        s.ks.data  = [];
        s.ks.lens  = 0;
        s.ks.index = [];

        s.tick.state = 0;
        s.tick.count = s.record.count;
        s.tick.tset  = 0;
        s.tick.freq  = 0;
    end

    function open( s )
        fopen(s.serial);
    end

    function close( s )
        fclose(s.serial);
    end

    function data = read( s, bytes, type )
        data = fread(s.serial, bytes, type);
    end

    function bytes = write( s, data, type )
        fwrite(s.serial, data, type);
        bytes = length(data);
    end

    function delay( ~, delay )
        pause(delay);
    end

    function setBaudRate( s, baudRate )
        s.baudRate = baudRate;
        s.serial.baudRate = s.baudRate;
    end

    function setInputBufferSize( s, bufferSize )
        s.inputBufferSize = bufferSize;
        s.serial.InputBufferSize = s.inputBufferSize;
    end

    function setRecordBufferSize( s, bufferSize )
        s.record.bufferSize = bufferSize;
        s.record.info = zeros(4, s.record.bufferSize);
        s.record.data = zeros(s.packet.maxLens, s.record.bufferSize);
    end

    function setRecvThreshold( s, threshold )
        s.packet.recvThreshold = threshold;
    end

    % [data, info, count] = s.packetRecv();
    function varargout = packetRecv( s )

        % default value
        s.packet.info = [];
        s.packet.data = [];
        s.packet.availableCount = [];
        s.packet.availableIndex = [];

        % start to read
        bytes = get(s.serial, 'BytesAvailable');
        if bytes > s.packet.recvThreshold
            s.packet.recvData = fread(s.serial, bytes, 'uint8');
            s.packet.recvBuffer = [s.packet.recvBuffer; s.packet.recvData];
            s.packet.recvBuffSize = size(s.packet.recvBuffer, 1);

            % find available packet
            packetIndex = find(s.packet.recvBuffer == 75);   % 'K'
            if  ~isempty(packetIndex) && packetIndex(end) > s.packet.recvBuffSize - 7
                packetIndex(end) = [];
            end
            if ~isempty(packetIndex)
                % check packet hrader
                subIndex = find(s.packet.recvBuffer(packetIndex + 1) == 83);   % 'S'
                if ~isempty(subIndex)
                    packetIndex = packetIndex(subIndex);
                    packetLens  = s.packet.recvBuffer(packetIndex + 2);

                    % check packet data length
                    subIndex = find(packetLens >= 8);
                    if ~isempty(subIndex)
                        packetIndex = packetIndex(subIndex);
                        packetLens  = packetLens(subIndex);
                        for i = size(packetIndex) : -1 : 1
                            if  packetIndex(i) + packetLens(i) - 1 > s.packet.recvBuffSize
                                packetIndex(i) = [];
                                packetLens(i)  = [];
                            end
                        end
                        % check finish signal
                        subIndex = find(s.packet.recvBuffer(packetIndex + packetLens - 2) == 13);   % '\r'
                        if ~isempty(subIndex)
                            packetIndex = packetIndex(subIndex);
                            packetLens = s.packet.recvBuffer(packetIndex + 2);
                            subIndex = find(s.packet.recvBuffer(packetIndex + packetLens - 1) == 10);   % '\n'
                            if ~isempty(subIndex)
                                s.packet.availableIndex = packetIndex(subIndex);
                                s.packet.availableCount = size(s.packet.availableIndex, 1);

                                % get available packet information and data
                                s.packet.data = zeros(s.packet.maxLens, s.packet.availableCount);
                                s.packet.info = zeros(4, s.packet.availableCount);
                                s.packet.info(1, :) = s.packet.recvBuffer(s.packet.availableIndex + 2)';    % length
                                s.packet.info(2, :) = s.packet.recvBuffer(s.packet.availableIndex + 3)';    % command 1
                                s.packet.info(3, :) = s.packet.recvBuffer(s.packet.availableIndex + 4)';    % command 2
                                s.packet.info(4, :) = s.packet.recvBuffer(s.packet.availableIndex + 5)';    % data type

                                s.record.count = s.record.count + s.packet.availableCount;
                                s.record.totalBytes = s.record.totalBytes + sum(s.packet.info(1, :));

                                for i = 1 : s.packet.availableCount
                                    if s.packet.info(1, i) == 8
                                        s.packet.data(:, i) = zeros(s.packet.maxLens, 1);
                                    else
                                        idx  = s.packet.availableIndex(i);
                                        typ  = s.getDataType(s.packet.info(4, i));
                                        lens = (s.packet.info(1, i) - 8) / s.getDataByte(s.packet.info(4, i));
                                        if lens > s.packet.maxLens
                                            s.packet.data(s.packet.maxLens + 1 : lens, :) = zeros(lens - s.packet.maxLens, size(s.packet.data, 2));
                                            s.packet.maxLens = lens;
                                        end
                                        convdata = typecast(uint8(s.packet.recvBuffer(idx + 6 : idx + s.packet.info(1, i) - 3)), typ);
                                        s.packet.data(:, i) = [convdata; zeros(s.packet.maxLens - size(convdata, 1), 1)];
                                    end
                                end

                                % update recv buffer & length
                                leastIndex = s.packet.availableIndex(end) + s.packet.info(1, end) - 1;
                                s.packet.recvBuffer(1 : leastIndex) = [];

                                % save to buffer
                                if size(s.record.data, 1) < s.packet.maxLens
                                    s.record.data(end + 1 : s.packet.maxLens, :) = zeros(s.packet.maxLens - size(s.record.data, 1), size(s.record.data, 2));
                                end
                                s.record.data = [s.record.data(:, s.packet.availableCount + 1 : end), s.packet.data];
                                s.record.info = [s.record.info(:, s.packet.availableCount + 1 : end), s.packet.info];

                                s.ks.lens = s.record.count;
                                s.ks.data = s.getRecordData();
                                s.ks.info = s.getRecordInfo();
                            end
                        end
                    end
                end
            end
        end
        varargout = { s.packet.data, s.packet.info, s.packet.availableCount };
    end

    % bytes = s.packetSend();                     ->  null command
    % bytes = s.packetSend(command);              ->  just send command
    % bytes = s.packetSend(command, data);        ->  auto use data type
    % bytes = s.packetSend(command, data, type);  ->  
    function bytes = packetSend( s, varargin )
        switch nargin
            case 1
                type     = s.getDataTypeIndex('nulltype');
                sendbuff = uint8(['KS', 8, 0, 0, type, 13, 10]);
            case 2
                command  = varargin{1};
                type     = s.getDataTypeIndex('nulltype');
                sendbuff = uint8(['KS', 8, command(1), command(2), type, 13, 10]);
            case 3
                command  = varargin{1};
                data     = varargin{2};
                type     = s.getDataTypeIndex(class(data));
                [m, i]   = max(size(data));
                lens     = 8 + s.getDataByte(type) * m;
                if i == 1
                    data = data(:, 1)';
                elseif i == 2
                    data = data(1, :);
                end
                convdata = typecast(data, 'uint8');
                sendbuff = uint8(['KS', lens, command(1), command(2), type, convdata, 13, 10]);
            case 4
                command  = varargin{1};
                data     = varargin{2};
                typeStr  = varargin{3};
                type     = s.getDataTypeIndex(typeStr);
                [m, i]   = max(size(data));
                lens     = 8 + s.getDataByte(type) * m;
                if i == 1
                    data = data(:, 1)';
                elseif i == 2
                    data = data(1, :);
                end
                switch typeStr
                    case 'int8',    convdata = typecast(int8(data),   'uint8');
                    case 'int16',   convdata = typecast(int16(data),  'uint8');
                    case 'int32',   convdata = typecast(int32(data),  'uint8');
                    case 'int64',   convdata = typecast(int64(data),  'uint8');
                    case 'uint8',   convdata = typecast(uint8(data),  'uint8');
                    case 'uint16',  convdata = typecast(uint16(data), 'uint8');
                    case 'uint32',  convdata = typecast(uint32(data), 'uint8');
                    case 'uint64',  convdata = typecast(uint64(data), 'uint8');
                    case 'single',  convdata = typecast(single(data), 'uint8');
                    case 'double',  convdata = typecast(double(data), 'uint8');
                end
                sendbuff = uint8(['KS', lens, command(1), command(2), type, convdata, 13, 10]);
        end
        s.write(sendbuff, 'uint8');
        bytes = size(sendbuff, 2);

    end

    % freq = s.getFreq(unit);                     ->  use system clock to calculate freq
    % freq = s.getFreq(index, lengrh, unit);      ->  use packet sec/msc to calculate freq
    function freq = getFreq( s, varargin )
        switch nargin
            case 2
                unit = varargin{1};
                if s.tick.state
                    s.tick.tset = toc;
                    if s.tick.tset >= unit
                        s.tick.state = 0;
                        s.tick.freq  = fix((s.record.count - s.tick.count) / s.tick.tset);
                        s.tick.count = s.record.count;
                        tic;
                    end
                else
                    s.tick.tset = toc;
                    if s.tick.tset >= unit
                        s.tick.state = 1;
                        s.tick.freq  = fix((s.record.count - s.tick.count) / s.tick.tset);
                        s.tick.count = s.record.count;
                        tic;
                    end
                end
                freq = s.tick.freq;
            case 4
                index  = varargin{1};
                length = varargin{2};
                unit   = varargin{3};
                sec_s = s.record.data(index(1), end - length) + s.record.data(index(2), end - length) * unit;
                sec_e = s.record.data(index(1), end) + s.record.data(index(2), end) * unit;
                freq = fix(length / (sec_e - sec_s) * 100  + 1e-5) / 100;
        end
    end

    % time = s.getTime(index, type, unit);        ->  type ~= 0 : return total seconds
    %                                             ->  type  = 0 : return [min, sec, msc]
    function varargout = getTime( s, index, type, unit )
        t = s.record.data(index(1), end) + s.record.data(index(2), end) * unit;
        if type
            varargout = {t};
        else
            msc = fix((t - fix(t)) / unit + 1e-5);
            sec = mod(fix(t), 60);
            min = fix(fix(t) / 60);
            varargout = {[min, sec, msc]};
        end
    end

    function data = getRecordData( s )
        if s.record.count < s.record.bufferSize
            data = s.record.data(:, end - s.record.count + 1 : end);
        else
            data = s.record.data;
        end
    end

    function data = getRecordInfo( s )
        if s.record.count < s.record.bufferSize
            data = s.record.info(:, end - s.record.count + 1 : end);
        else
            data = s.record.info;
        end
    end

    function save2mat( s, name, index )
        fprintf('\n');
        date = fix(clock);
        tag  = sprintf('_%04i%02i%02i_%02i%02i%02i.mat', date);
        fileName = strcat(name, tag);
        fprintf(fileName);
        fprintf('  SAVE... ');

        s.ks.index = index;
        ks = s.ks;
        save(fileName, 'ks');
        fprintf('OK\n');
    end

end

methods (Access = private)

    function typ = getDataType( ~, index )
        switch index
            case 0,   typ = 'null';    % 0x00, 8'b 0000 0000
            case 17,  typ = 'int8';    % 0x11, 8'b 0001 0001
            case 18,  typ = 'int16';   % 0x12, 8'b 0001 0010
            case 20,  typ = 'int32';   % 0x14, 8'b 0001 0100
            case 24,  typ = 'int64';   % 0x18, 8'b 0001 1000
            case 33,  typ = 'uint8';   % 0x21, 8'b 0010 0001
            case 34,  typ = 'uint16';  % 0x22, 8'b 0010 0010
            case 36,  typ = 'uint32';  % 0x24, 8'b 0010 0100
            case 40,  typ = 'uint64';  % 0x28, 8'b 0010 1000
            case 68,  typ = 'single';  % 0x44, 8'b 0100 0100
            case 72,  typ = 'double';  % 0x48, 8'b 0100 1000
        end
    end

    function byte = getDataByte( ~, index )
        switch index
            case 0,   byte = 0;  % nulltype
            case 17,  byte = 1;  % int8
            case 18,  byte = 2;  % int16
            case 20,  byte = 4;  % int32
            case 24,  byte = 8;  % int64
            case 33,  byte = 1;  % uint8
            case 34,  byte = 2;  % uint16
            case 36,  byte = 4;  % uint32
            case 40,  byte = 8;  % uint64
            case 68,  byte = 4;  % single
            case 72,  byte = 8;  % double
        end
    end

    function index = getDataTypeIndex( ~, type )
        switch type
            case 'nulltype', index = 0;
            case 'int8',     index = 17;
            case 'int16',    index = 18;
            case 'int32',    index = 20;
            case 'int64',    index = 24;
            case 'uint8',    index = 33;
            case 'uint16',   index = 34;
            case 'uint32',   index = 36;
            case 'uint64',   index = 40;
            case 'single',   index = 68;
            case 'double',   index = 72;
        end
    end

    function bytes = sizeof( ~, type )
        switch type
            case 'int8',    bytes = 1;
            case 'int16',   bytes = 2;
            case 'int32',   bytes = 4;
            case 'int64',   bytes = 8;
            case 'uint8',   bytes = 1;
            case 'uint16',  bytes = 2;
            case 'uint32',  bytes = 4;
            case 'uint64',  bytes = 8;
            case 'single',  bytes = 4;
            case 'double',  bytes = 8;
        end
    end

end

end