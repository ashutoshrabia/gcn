function W = constructW(fea,options)

bSpeed  = 1;

if (~exist('options','var'))
   options = [];
end

if isfield(options,'Metric')
    warning('This function has been changed and the Metric is no longer be supported');
end


if ~isfield(options,'bNormalized')
    options.bNormalized = 0;
end

%=================================================
if ~isfield(options,'NeighborMode')
    options.NeighborMode = 'KNN';
end

switch lower(options.NeighborMode)
    case {lower('KNN')}  %For simplicity, we include the data point itself in the kNN
        if ~isfield(options,'k')
            options.k = 5;
        end
    case {lower('Supervised')}
        if ~isfield(options,'bLDA')
            options.bLDA = 0;
        end
        if options.bLDA
            options.bSelfConnected = 1;
        end
        if ~isfield(options,'k')
            options.k = 0;
        end
        if ~isfield(options,'gnd')
            error('Label(gnd) should be provided under ''Supervised'' NeighborMode!');
        end
        if ~isempty(fea) && length(options.gnd) ~= size(fea,1)
            error('gnd doesn''t match with fea!');
        end
    otherwise
        error('NeighborMode does not exist!');
end

%=================================================

if ~isfield(options,'WeightMode')
    options.WeightMode = 'HeatKernel';
end

bBinary = 0;
bCosine = 0;
switch lower(options.WeightMode)
    case {lower('Binary')}
        bBinary = 1; 
    case {lower('HeatKernel')}
        if ~isfield(options,'t')
            nSmp = size(fea,1);
            if nSmp > 3000
                D = EuDist2(fea(randsample(nSmp,3000),:));
            else
                D = EuDist2(fea);
            end
            options.t = mean(mean(D));
        end
    case {lower('Cosine')}
        bCosine = 1;
    otherwise
        error('WeightMode does not exist!');
end

%=================================================

if ~isfield(options,'bSelfConnected')
    options.bSelfConnected = 0;
end

%=================================================

if isfield(options,'gnd') 
    nSmp = length(options.gnd);
else
    nSmp = size(fea,1);
end
maxM = 62500000; %500M
BlockSize = floor(maxM/(nSmp*3));


if strcmpi(options.NeighborMode,'Supervised')
    Label = unique(options.gnd);
    nLabel = length(Label);
    if options.bLDA
        G = zeros(nSmp,nSmp);
        for idx=1:nLabel
            classIdx = options.gnd==Label(idx);
            G(classIdx,classIdx) = 1/sum(classIdx);
        end
        W = sparse(G);
        return;
    end
    
    switch lower(options.WeightMode)
        case {lower('Binary')}
            if options.k > 0
                G = zeros(nSmp*(options.k+1),3);
                idNow = 0;
                for i=1:nLabel
                    classIdx = find(options.gnd==Label(i));
                    D = EuDist2(fea(classIdx,:),[],0);
                    [~, idx] = sort(D,2); % sort each row
                    clear D dump;
                    idx = idx(:,1:options.k+1);
                    
                    nSmpClass = length(classIdx)*(options.k+1);
                    G(idNow+1:nSmpClass+idNow,1) = repmat(classIdx,[options.k+1,1]);
                    G(idNow+1:nSmpClass+idNow,2) = classIdx(idx(:));
                    G(idNow+1:nSmpClass+idNow,3) = 1;
                    idNow = idNow+nSmpClass;
                    clear idx
                end
                G = sparse(G(:,1),G(:,2),G(:,3),nSmp,nSmp);
                G = max(G,G');
            else
                G = zeros(nSmp,nSmp);
                for i=1:nLabel
                    classIdx = find(options.gnd==Label(i));
                    G(classIdx,classIdx) = 1;
                end
            end
            
            if ~options.bSelfConnected
                for i=1:size(G,1)
                    G(i,i) = 0;
                end
            end
            
            W = sparse(G);
        case {lower('HeatKernel')}
            if options.k > 0
                G = zeros(nSmp*(options.k+1),3);
                idNow = 0;
                for i=1:nLabel
                    classIdx = find(options.gnd==Label(i));
                    D = EuDist2(fea(classIdx,:),[],0);
                    [dump, idx] = sort(D,2); % sort each row
                    clear D;
                    idx = idx(:,1:options.k+1);
                    dump = dump(:,1:options.k+1);
                    dump = exp(-dump/(2*options.t^2));
                    
                    nSmpClass = length(classIdx)*(options.k+1);
                    G(idNow+1:nSmpClass+idNow,1) = repmat(classIdx,[options.k+1,1]);
                    G(idNow+1:nSmpClass+idNow,2) = classIdx(idx(:));
                    G(idNow+1:nSmpClass+idNow,3) = dump(:);
                    idNow = idNow+nSmpClass;
                    clear dump idx
                end
                G = sparse(G(:,1),G(:,2),G(:,3),nSmp,nSmp);
            else
                G = zeros(nSmp,nSmp);
                for i=1:nLabel
                    classIdx = find(options.gnd==Label(i));
                    D = EuDist2(fea(classIdx,:),[],0);
                    D = exp(-D/(2*options.t^2));
                    G(classIdx,classIdx) = D;
                end
            end
            
            if ~options.bSelfConnected
                for i=1:size(G,1)
                    G(i,i) = 0;
                end
            end

            W = sparse(max(G,G'));
        case {lower('Cosine')}
            if ~options.bNormalized
                fea = NormalizeFea(fea);
            end

            if options.k > 0
                G = zeros(nSmp*(options.k+1),3);
                idNow = 0;
                for i=1:nLabel
                    classIdx = find(options.gnd==Label(i));
                    D = fea(classIdx,:)*fea(classIdx,:)';
                    [dump, idx] = sort(-D,2); % sort each row
                    clear D;
                    idx = idx(:,1:options.k+1);
                    dump = -dump(:,1:options.k+1);
                    
                    nSmpClass = length(classIdx)*(options.k+1);
                    G(idNow+1:nSmpClass+idNow,1) = repmat(classIdx,[options.k+1,1]);
                    G(idNow+1:nSmpClass+idNow,2) = classIdx(idx(:));
                    G(idNow+1:nSmpClass+idNow,3) = dump(:);
                    idNow = idNow+nSmpClass;
                    clear dump idx
                end
                G = sparse(G(:,1),G(:,2),G(:,3),nSmp,nSmp);
            else
                G = zeros(nSmp,nSmp);
                for i=1:nLabel
                    classIdx = find(options.gnd==Label(i));
                    G(classIdx,classIdx) = fea(classIdx,:)*fea(classIdx,:)';
                end
            end

            if ~options.bSelfConnected
                for i=1:size(G,1)
                    G(i,i) = 0;
                end
            end

            W = sparse(max(G,G'));
        otherwise
            error('WeightMode does not exist!');
    end
    return;
end


if bCosine && ~options.bNormalized
    Normfea = NormalizeFea(fea);
end

if strcmpi(options.NeighborMode,'KNN') && (options.k > 0)
    if ~(bCosine && options.bNormalized)
        G = zeros(nSmp*(options.k+1),3);
        for i = 1:ceil(nSmp/BlockSize)
            if i == ceil(nSmp/BlockSize)
                smpIdx = (i-1)*BlockSize+1:nSmp;
                dist = EuDist2(fea(smpIdx,:),fea,0);
                if bSpeed
                    nSmpNow = length(smpIdx);
                    dump = zeros(nSmpNow,options.k+1);
                    idx = dump;
                    for j = 1:options.k+1
                        [dump(:,j),idx(:,j)] = min(dist,[],2);
                        temp = (idx(:,j)-1)*nSmpNow+(1:nSmpNow)';
                        dist(temp) = 1e100;
                    end
                else
                    [dump idx] = sort(dist,2); % sort each row
                    idx = idx(:,1:options.k+1);
                    dump = dump(:,1:options.k+1);
                end
                
                if ~bBinary
                    if bCosine
                        dist = Normfea(smpIdx,:)*Normfea';
                        dist = full(dist);
                        linidx = (1:size(idx,1))';
                        dump = dist(sub2ind(size(dist),linidx(:,ones(1,size(idx,2))),idx));
                    else
                        dump = exp(-dump/(2*options.t^2));
                    end
                end
                
                G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),1) = repmat(smpIdx',[options.k+1,1]);
                G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),2) = idx(:);
                if ~bBinary
                    G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),3) = dump(:);
                else
                    G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),3) = 1;
                end
            else
                smpIdx = (i-1)*BlockSize+1:i*BlockSize;
            
                dist = EuDist2(fea(smpIdx,:),fea,0);
                
                if bSpeed
                    nSmpNow = length(smpIdx);
                    dump = zeros(nSmpNow,options.k+1);
                    idx = dump;
                    for j = 1:options.k+1
                        [dump(:,j),idx(:,j)] = min(dist,[],2);
                        temp = (idx(:,j)-1)*nSmpNow+(1:nSmpNow)';
                        dist(temp) = 1e100;
                    end
                else
                    [dump idx] = sort(dist,2); % sort each row
                    idx = idx(:,1:options.k+1);
                    dump = dump(:,1:options.k+1);
                end
                
                if ~bBinary
                    if bCosine
                        dist = Normfea(smpIdx,:)*Normfea';
                        dist = full(dist);
                        linidx = (1:size(idx,1))';
                        dump = dist(sub2ind(size(dist),linidx(:,ones(1,size(idx,2))),idx));
                    else
                        dump = exp(-dump/(2*options.t^2));
                    end
                end
                
                G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),1) = repmat(smpIdx',[options.k+1,1]);
                G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),2) = idx(:);
                if ~bBinary
                    G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),3) = dump(:);
                else
                    G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),3) = 1;
                end
            end
        end

        W = sparse(G(:,1),G(:,2),G(:,3),nSmp,nSmp);
    else
        G = zeros(nSmp*(options.k+1),3);
        for i = 1:ceil(nSmp/BlockSize)
            if i == ceil(nSmp/BlockSize)
                smpIdx = (i-1)*BlockSize+1:nSmp;
                dist = fea(smpIdx,:)*fea';
                dist = full(dist);
                if bSpeed
                    nSmpNow = length(smpIdx);
                    dump = zeros(nSmpNow,options.k+1);
                    idx = dump;
                    for j = 1:options.k+1
                        [dump(:,j),idx(:,j)] = max(dist,[],2);
                        temp = (idx(:,j)-1)*nSmpNow+(1:nSmpNow)';
                        dist(temp) = 0;
                    end
                else
                    [dump idx] = sort(-dist,2); % sort each row
                    idx = idx(:,1:options.k+1);
                    dump = -dump(:,1:options.k+1);
                end

                G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),1) = repmat(smpIdx',[options.k+1,1]);
                G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),2) = idx(:);
                G((i-1)*BlockSize*(options.k+1)+1:nSmp*(options.k+1),3) = dump(:);
            else
                smpIdx = (i-1)*BlockSize+1:i*BlockSize;
                dist = fea(smpIdx,:)*fea';
                dist = full(dist);
                
                if bSpeed
                    nSmpNow = length(smpIdx);
                    dump = zeros(nSmpNow,options.k+1);
                    idx = dump;
                    for j = 1:options.k+1
                        [dump(:,j),idx(:,j)] = max(dist,[],2);
                        temp = (idx(:,j)-1)*nSmpNow+(1:nSmpNow)';
                        dist(temp) = 0;
                    end
                else
                    [dump idx] = sort(-dist,2); % sort each row
                    idx = idx(:,1:options.k+1);
                    dump = -dump(:,1:options.k+1);
                end

                G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),1) = repmat(smpIdx',[options.k+1,1]);
                G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),2) = idx(:);
                G((i-1)*BlockSize*(options.k+1)+1:i*BlockSize*(options.k+1),3) = dump(:);
            end
        end

        W = sparse(G(:,1),G(:,2),G(:,3),nSmp,nSmp);
    end
    
    if bBinary
        W(logical(W)) = 1;
    end
    
    if isfield(options,'bSemiSupervised') && options.bSemiSupervised
        tmpgnd = options.gnd(options.semiSplit);
        
        Label = unique(tmpgnd);
        nLabel = length(Label);
        G = zeros(sum(options.semiSplit),sum(options.semiSplit));
        for idx=1:nLabel
            classIdx = tmpgnd==Label(idx);
            G(classIdx,classIdx) = 1;
        end
        Wsup = sparse(G);
        if ~isfield(options,'SameCategoryWeight')
            options.SameCategoryWeight = 1;
        end
        W(options.semiSplit,options.semiSplit) = (Wsup>0)*options.SameCategoryWeight;
    end
    
    if ~options.bSelfConnected
        W = W - diag(diag(W));
    end

    if isfield(options,'bTrueKNN') && options.bTrueKNN
        
    else
        W = max(W,W');
    end
    
    return;
end



