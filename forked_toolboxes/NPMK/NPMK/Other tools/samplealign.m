function [varargout] = samplealign(varargin)
%SAMPLEALIGN takes 1+ structs generated by running openNSx on data that was
% recorded with Gemini Hubs and NSPs in versions 7.6.0 and later and aligns
% files to their expected sampling rates based off PTP time. Alignment
% occurs by removing frames of data if the sampling rate is faster than
% desired, and duplicating frames if the sampling rate is slower than 
% desired.
% SAMPLEALIGN will add/remove frames to/from the structures evenly
% dispersed throughout the duration of the recording.
%
% Inputs
%   varargin{} = add however many structures generated by openNSx you want
%       to have aligned, separated by commas as individual arguments. The
%       structures generated by openNSx must have a time resolution of 1e9
%       and have every continuous sample timestamped.
%       (at least one, more than one optional)
%
% Outputs
%   varargout{} = output arguments that must match the number of optional
%       input arguments put into varargin{}. The output structures will
%       have one timestamp per segment of data.
%       (at least one, nargout must equal nargin)
%
% Versions:
% 1.0.0 = Published 2023/03 DK
%   - Initial commit

% Basic input/output health checking
narginchk(1,inf);

% Generate structures for each field that is affected by this function;
Data = cell(nargin,1);
fnames = cell(nargin,1);
ts_diffs = cell(nargin,1);
samplingrates = cell(nargin,1);
timeres = zeros(nargin,1);
freq = zeros(nargin,1);
datalengths = cell(nargin,1);
durations = cell(nargin,1);
segmentinds = cell(nargin,1);
segmenteddata = cell(nargin,1);
segmentedts = cell(nargin,1);

for n = 1:nargin   
    Data{n} = varargin{n};
end

if nargin ~= nargout
    error('There must be the same number of input and output arguments.')
end



% High level input data checking.
for i=1:nargin
    fnames{i} = Data{i}.MetaTags.Filename;
    % Make sure the structures are correct
    if ~isfield(Data{i},'MetaTags') && ~isfield(Data{i},'Data') && ~isfield(Data{i},'RawData') && ~isfield(Data{i},'ElectrodesInfo')
        error('All input arguments must be data structs generated by openNSx.')
    elseif Data{i}.MetaTags.TimeRes ~= 1e9 && ~strcmp(Data{i}.MetaTags.FileSpec,'3.0') && length(Data{i}.MetaTags.DataPoints) ~= sum(Data{i}.MetaTags.DataPoints)
        error('Struct input arguments generated by openNSx must have nanosecond resolution, been generated by Central v7.6.0, and have one timestamp per sample.')
    end

    % Identifying gaps between data points
    ts_diffs{i} = diff(double(Data{i}.MetaTags.Timestamp));

    % Extract the claimed resolution and sampling frequency of each
    % recording
    timeres(i) = double(Data{i}.MetaTags.TimeRes);
    freq(i) = double(Data{i}.MetaTags.SamplingFreq);

    % Clock drift patch kills ability to segment files. This check will
    % allow segments to be reintroduced into the data structures if a
    % timestamp difference of 200% greater than expected is identified
    segmentinds{i} = find([ts_diffs{i}(1) ts_diffs{i}] > (2*timeres(i)/freq(i)));
    segmenteddata{i} = cell(length(segmentinds{i})+1,1);
    segmentedts{i} = cell(length(segmentinds{i})+1,1);
    if ~isempty(segmentinds{i})
        for ii = 1:length(segmentinds{i})+1
            if ii == 1
                inds = 1:segmentinds{i}(ii)-1;
            elseif ii <= length(segmentinds{i})
                inds = segmentinds{i}(ii-1):segmentinds{i}(ii)-1;
            else
                inds = segmentinds{i}(ii-1):length(Data{i}.Data);
            end

            % Fill stucts with values needed for later calculations for
            % alignment
            segmenteddata{i}{ii} = Data{i}.Data(:,inds);
            segmentedts{i}{ii} = Data{i}.MetaTags.Timestamp(:,inds);
            datalengths{i}(ii) = length(inds);
            durations{i}(ii) = segmentedts{i}{ii}(end)- segmentedts{i}{ii}(1);

            % Calculate the ratio between time gaps and expected time gap 
            % based on the sampling rate of the recording. A recording
            % where the claimed sampling rate and true sampling rate based
            % off PTP time are identical will have a ratio of 1;
            samplingrates{i}(ii) = durations{i}(ii)/datalengths{i}(ii)/timeres(i)*freq(i);
        end
    else
        segmenteddata{i} = Data{i}.Data;
        segmentedts{i} = Data{i}.MetaTags.Timestamp;
        datalengths{i} = length(Data{i}.Data);
        durations{i} = segmentedts{i}(end) - segmentedts{i}(1);
        samplingrates{i} = durations{i}/datalengths{i}/timeres(i)*freq(i);
    end

end

if length(fnames) ~= length(unique(fnames))
    error('Do not attempt to align data collected from the same Hub or NSP duirng the same recording. Clock drift only occurs between unique units.')
end


%% Perform drift correction
% Create temporary data structures to be acted upo by drift correction
tempdata = cell(length(Data),1);
tempts = cell(length(Data),1);

for j=1:nargin
    % Remove affected elements from the structure
    Data{j} = rmfield(Data{j},'Data');
    Data{j}.MetaTags = rmfield(Data{j}.MetaTags,{'Timestamp','DataPoints','DataDurationSec','DataPointsSec'});

    % Data with pauses in it has a different underlying structure than data
    % without pauses: NSx.Data is a cell for data with pauses and is an 
    % array with no pauses. Two streams of logic needed to handle the
    % difference in outputs openNSx generates.
    if length(samplingrates{j}) > 1
        for jj = 1:length(samplingrates{j})
            startind = 1;
            % Calculate the number of samples that should be added or
            % removed
            addedsamples = round((samplingrates{j}(jj)-1)*datalengths{j}(jj));
    
            % Establish where the points should be added or removed
            gap = round(datalengths{j}(jj)/(abs(addedsamples)+1));
            tempts{j}{jj} = segmentedts{j}{jj}(1);
            tempdata{j}{jj} = [];
            
            % Repeat frames when samples need to be added. Delete frames
            % when samples need to be taken away.
            if addedsamples > 0
                warning('%i samples added to %s segment %i', addedsamples, [Data{j}.MetaTags.Filename Data{j}.MetaTags.FileExt], jj)
                while startind < datalengths{j}(jj)
                    % Error correction for overflow beyond the .Data length
                    if startind+gap < datalengths{j}(jj)
                        tempdata{j}{jj} = [tempdata{j}{jj} segmenteddata{j}{jj}(:,startind:(startind+gap))];
                    else
                        tempdata{j}{jj} = [tempdata{j}{jj} segmenteddata{j}{jj}(:,startind:end)];
                    end
                    startind = startind + gap;
                end
            elseif addedsamples < 0
                warning('%i samples removed from %s segment %i', abs(addedsamples), [Data{j}.MetaTags.Filename Data{j}.MetaTags.FileExt], jj)
                while startind < datalengths{j}(jj)
                    % Error correction for overflow beyond the .Data length
                    if startind+gap < datalengths{j}(jj)
                        tempdata{j}{jj} = [tempdata{j}{jj} segmenteddata{j}{jj}(:,startind:(startind+gap-1))];
                    else
                        tempdata{j}{jj} = [tempdata{j}{jj} segmenteddata{j}{jj}(:,startind:end)];
                    end
                    startind = startind + gap + 1;
                end
            else
                tempdata{j}{jj} = segmenteddata{j}{jj};
            end            
        end
    else
        % Repeat above logic for cases where NSx.Data is an array
        startind = 1;
        addedsamples = round((samplingrates{j}-1)*datalengths{j});

        % Establish where the extra points should be added
        gap = round(datalengths{j}/(abs(addedsamples)+1));
        tempts{j} = segmentedts{j}(1);
        tempdata{j} = [];
        
        if addedsamples > 0
            warning('%i samples added to %s', addedsamples, [Data{j}.MetaTags.Filename Data{j}.MetaTags.FileExt])
            while startind < datalengths{j}
                if startind+gap < datalengths{j}
                    tempdata{j} = [tempdata{j} segmenteddata{j}(:,startind:(startind+gap))];
                else
                    tempdata{j} = [tempdata{j} segmenteddata{j}(:,startind:end)];
                end
                startind = startind + gap;
            end
        elseif addedsamples < 0
            warning('%i samples removed from %s', abs(addedsamples), [Data{j}.MetaTags.Filename Data{j}.MetaTags.FileExt])
            while startind < datalengths{j}
                if startind+gap < datalengths{j}
                    tempdata{j} = [tempdata{j} segmenteddata{j}(:,startind:(startind+gap-1))];
                else
                    tempdata{j} = [tempdata{j} segmenteddata{j}(:,startind:end)];
                end
                startind = startind + gap + 1;
            end
        else
            tempdata{j} = segmenteddata{j};
        end
    end

    % Fill data to prepare for outputs.
    Data{j}.Data = tempdata{j};
    if iscell(tempts{j})
        for jj = 1:length(tempts{j})
            Data{j}.MetaTags.Timestamp(jj) = tempts{j}{jj}(1);
            Data{j}.MetaTags.DataPoints(jj) = length(Data{j}.Data{jj});
            Data{j}.MetaTags.DataDurationSec(jj) = floor(length(Data{j}.Data{jj})/freq(j));
            Data{j}.MetaTags.DataPointsSec(jj) = floor(length(Data{j}.Data{jj})/freq(j));
        end
    else
        Data{j}.MetaTags.Timestamp = tempts{j}(1);
        Data{j}.MetaTags.DataPoints = length(Data{j}.Data);
        Data{j}.MetaTags.DataDurationSec = floor(length(Data{j}.Data)/freq(j));
        Data{j}.MetaTags.DataPointsSec = floor(length(Data{j}.Data)/freq(j));
    end
    
    
end

% Complete the output arguments.
structout = cell(nargin,1);
for n=1:nargout
    structout{n} = Data{n};
end

varargout = Data;