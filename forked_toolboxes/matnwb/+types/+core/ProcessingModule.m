classdef ProcessingModule < types.core.NWBContainer & types.untyped.GroupClass
% PROCESSINGMODULE A collection of processed data.


% REQUIRED PROPERTIES
properties
    description; % REQUIRED (char) Description of this collection of processed data.
end
% OPTIONAL PROPERTIES
properties
    dynamictable; % OPTIONAL (DynamicTable) Tables stored in this collection.
    nwbdatainterface; % OPTIONAL (NWBDataInterface) Data objects stored in this collection.
end

methods
    function obj = ProcessingModule(varargin)
        % PROCESSINGMODULE Constructor for ProcessingModule
        obj = obj@types.core.NWBContainer(varargin{:});
        [obj.dynamictable, ivarargin] = types.util.parseConstrained(obj,'dynamictable', 'types.hdmf_common.DynamicTable', varargin{:});
        varargin(ivarargin) = [];
        [obj.nwbdatainterface, ivarargin] = types.util.parseConstrained(obj,'nwbdatainterface', 'types.core.NWBDataInterface', varargin{:});
        varargin(ivarargin) = [];
        
        p = inputParser;
        p.KeepUnmatched = true;
        p.PartialMatching = false;
        p.StructExpand = false;
        addParameter(p, 'description',[]);
        misc.parseSkipInvalidName(p, varargin);
        obj.description = p.Results.description;
        if strcmp(class(obj), 'types.core.ProcessingModule')
            types.util.checkUnset(obj, unique(varargin(1:2:end)));
        end
    end
    %% SETTERS
    function obj = set.description(obj, val)
        obj.description = obj.validate_description(val);
    end
    function obj = set.dynamictable(obj, val)
        obj.dynamictable = obj.validate_dynamictable(val);
    end
    function obj = set.nwbdatainterface(obj, val)
        obj.nwbdatainterface = obj.validate_nwbdatainterface(val);
    end
    %% VALIDATORS
    
    function val = validate_description(obj, val)
        val = types.util.checkDtype('description', 'char', val);
        if isa(val, 'types.untyped.DataStub')
            if 1 == val.ndims
                valsz = [val.dims 1];
            else
                valsz = val.dims;
            end
        elseif istable(val)
            valsz = [height(val) 1];
        elseif ischar(val)
            valsz = [size(val, 1) 1];
        else
            valsz = size(val);
        end
        validshapes = {[1]};
        types.util.checkDims(valsz, validshapes);
    end
    function val = validate_dynamictable(obj, val)
        constrained = {'types.hdmf_common.DynamicTable'};
        types.util.checkSet('dynamictable', struct(), constrained, val);
    end
    function val = validate_nwbdatainterface(obj, val)
        constrained = {'types.core.NWBDataInterface'};
        types.util.checkSet('nwbdatainterface', struct(), constrained, val);
    end
    %% EXPORT
    function refs = export(obj, fid, fullpath, refs)
        refs = export@types.core.NWBContainer(obj, fid, fullpath, refs);
        if any(strcmp(refs, fullpath))
            return;
        end
        io.writeAttribute(fid, [fullpath '/description'], obj.description);
        if ~isempty(obj.dynamictable)
            refs = obj.dynamictable.export(fid, fullpath, refs);
        end
        if ~isempty(obj.nwbdatainterface)
            refs = obj.nwbdatainterface.export(fid, fullpath, refs);
        end
    end
end

end