clear; clc;

% Mixed-SNR TRAIN/VAL/TEST + held-out BER generator.
% Each train/val/test split combines every channel and SNR in cfg.snr.
% BER retains channel/SNR files for condition-wise curves.
% Select cfg.labelMode = 'qam' or 'channel' (the ONLY label-mode switch).
% Run the complete file, e.g. run('C:\dataset_for_train\gendata.m').
cfg.generatorVersion = 'GENDATA_DUAL_LABEL_MIXED_SNR_V6';
fprintf('[%s] Mixed-SNR training/validation/test + BER generator.\n', ...
    cfg.generatorVersion);
sourcePath = mfilename('fullpath');
assert(~isempty(sourcePath), ...
    'Save this complete script as gendata.m and run the saved file.');
rootDir = fileparts(sourcePath);
fprintf('Running file: %s.m\n', sourcePath);

cfg.seed = 17;
cfg.labelMode = 'channel';           % 'qam': TX 64-QAM constellation; 'channel': noise-free L-LTF H
% The mode is encoded in the destination folders to prevent mixing labels.
cfg.outputFolder = ['dataset_' cfg.labelMode];
cfg.generateTrainValTest = true; % default: generate TRAIN/VAL/TEST plus BER
cfg.existingTrainPolicy = 'new'; % occupied train folder -> numbered fresh folder ('skip' optional)
cfg.generateBER = true;
cfg.berOutputFolder = ['dataset_ber_' cfg.labelMode];
cfg.autoNewBERFolder = true;  % occupied BER folder -> dataset_ber_001, _002, ...
cfg.includeLLTF = false;       % false: X128 DATA-only; true: X384 with received L-LTF
% For channel estimation, cfg.includeLLTF=true is normally preferable.
cfg.saveMeta = true;            % aligned channel/SNR metadata for train/val/test
cfg.overwriteExisting = false; % SAFETY: false by default; set true only deliberately
cfg.modulationOrder = 64;       % this generator is specifically for 64-QAM
cfg.numDataSymbols = 1;         % keep 1 for exactly 104 target columns
cfg.selfTestOnly = false;     % true: run algebraic checks, write no dataset
cfg.smokeTest = false;        % true: 2 rows/condition in a separate folder

cfg.channelBandwidth = 'CBW20';
cfg.sampleRate = 20e6;
cfg.carrierFrequency = 5.25e9;
cfg.environmentalSpeedKmh = 0.62;
cfg.tailZeros = 64;
cfg.maxSyncOffset = 48;
cfg.channels = ["Model-A","Model-B","Model-C", "Model-D","Model-E","Model-F"];
cfg.channelKeys = ["tgn_a","tgn_b","tgn_c","tgn_d","tgn_e","tgn_f"];
cfg.snr = -3:3:18;              % COMMON train/val/test grid; mixed within each split
cfg.trainPerCondition = 3500;
cfg.valPerCondition = 1500;
cfg.testPerCondition = 1500;
cfg.snrBER = cfg.snr;
cfg.berPerCondition = 1500;
cfg.berSeedOffset = 6000000;

required = {'wlanTGnChannel','wlanNonHTConfig','wlanNonHTOFDMInfo', ...
    'wlanLLTF','wlanLLTFDemodulate','wlanLLTFChannelEstimate', ...
    'wlanConstellationMap','ofdmmod','ofdmdemod'};
for k = 1:numel(required)
    assert(exist(required{k}, 'file') ~= 0 || ...
        exist(required{k}, 'class') ~= 0, ...
        'Missing %s. Install/enable WLAN and Communications Toolboxes.', ...
        required{k});
end
validateattributes(cfg.modulationOrder, {'numeric'}, ...
    {'scalar','integer','positive'});
assert(cfg.modulationOrder == 64, 'This generator requires 64-QAM.');
validateattributes(cfg.numDataSymbols, {'numeric'}, ...
    {'scalar','integer','positive'});
assert(cfg.numDataSymbols == 1, ...
    'Exactly 104 targets requires cfg.numDataSymbols = 1.');
validateattributes(cfg.saveMeta, {'logical'}, {'scalar'});
validateattributes(cfg.includeLLTF, {'logical'}, {'scalar'});
validateattributes(cfg.overwriteExisting, {'logical'}, {'scalar'});
assert(ischar(cfg.labelMode) && isrow(cfg.labelMode) && ...
    any(strcmp(cfg.labelMode, {'qam','channel'})), ...
    'cfg.labelMode must be ''qam'' or ''channel''.');
validateattributes(cfg.generateTrainValTest, {'logical'}, {'scalar'});
validateattributes(cfg.generateBER, {'logical'}, {'scalar'});
validateattributes(cfg.autoNewBERFolder, {'logical'}, {'scalar'});
assert(ischar(cfg.existingTrainPolicy) && ...
    any(strcmp(cfg.existingTrainPolicy, {'skip','new'})), ...
    'cfg.existingTrainPolicy must be ''skip'' or ''new''.');
validateOutputName(cfg.outputFolder);
validateOutputName(cfg.berOutputFolder);
validateattributes(cfg.selfTestOnly, {'logical'}, {'scalar'});
validateattributes(cfg.smokeTest, {'logical'}, {'scalar'});
validateattributes(cfg.seed, {'numeric'}, ...
    {'scalar','integer','nonnegative','finite'});
validateattributes(cfg.berSeedOffset, {'numeric'}, ...
    {'scalar','integer','positive','finite'});
assert(cfg.generateTrainValTest || cfg.generateBER || cfg.selfTestOnly, ...
    'Enable at least one dataset family or cfg.selfTestOnly.');
for n = [cfg.trainPerCondition cfg.valPerCondition ...
        cfg.testPerCondition cfg.berPerCondition]
    validateattributes(n, {'numeric'}, {'scalar','integer','positive','finite'});
end
snrGrids = {cfg.snr, cfg.snrBER};
for k = 1:numel(snrGrids)
    grid = snrGrids{k};
    validateattributes(grid, {'numeric'}, {'vector','nonempty','integer','finite'});
    assert(numel(unique(grid)) == numel(grid), 'Duplicate SNR conditions.');
end
assert(numel(cfg.channels) == numel(cfg.channelKeys), ...
    'Channel profiles and channel keys must have equal lengths.');
assert(cfg.tailZeros >= cfg.maxSyncOffset, ...
    'tailZeros must be at least maxSyncOffset.');

ofdmInfo = wlanNonHTOFDMInfo('NonHT-Data', cfg.channelBandwidth);
lltfInfo = wlanNonHTOFDMInfo('L-LTF', cfg.channelBandwidth);
cfg.nFFT = ofdmInfo.FFTLength;
cfg.cpLength = ofdmInfo.CPLength;
cfg.activeFFTIndices = ofdmInfo.ActiveFFTIndices(:);
cfg.activeFrequencyIndices = ofdmInfo.ActiveFrequencyIndices(:);
cfg.dataIndices = ofdmInfo.DataIndices(:);
cfg.pilotIndices = ofdmInfo.PilotIndices(:);
cfg.dataFFTIndices = cfg.activeFFTIndices(cfg.dataIndices);
cfg.pilotFFTIndices = cfg.activeFFTIndices(cfg.pilotIndices);
cfg.nullFFTIndices = setdiff((1:cfg.nFFT).', cfg.activeFFTIndices);
cfg.numActive = numel(cfg.activeFFTIndices);
cfg.numData = numel(cfg.dataIndices);
cfg.numPilots = numel(cfg.pilotIndices);
cfg.numBPSCS = log2(cfg.modulationOrder);
cfg.nBits = cfg.numData*cfg.numBPSCS*cfg.numDataSymbols;
cfg.fftGain = cfg.nFFT / sqrt(cfg.numActive);
cfg.txPilots = repmat([1;1;1;-1], 1, cfg.numDataSymbols);
assert(cfg.nFFT == 64 && cfg.cpLength == 16 && ...
    cfg.numActive == 52 && cfg.numData == 48 && cfg.numPilots == 4, ...
    'This generator requires the CBW20 non-HT OFDM allocation.');
assert(isequal(sort([cfg.dataIndices; cfg.pilotIndices]), ...
    (1:cfg.numActive).'), 'DATA and pilot indices must partition active tones.');
assert(isequal(cfg.activeFrequencyIndices, [-26:-1 1:26].'), ...
    'Unexpected active-tone order.');
assert(isequal(cfg.activeFrequencyIndices(cfg.pilotIndices), [-21;-7;7;21]), ...
    'Unexpected pilot-tone order.');
assert(isequal(cfg.activeFFTIndices, lltfInfo.ActiveFFTIndices(:)), ...
    'L-LTF and DATA active-tone ordering must match.');
assert(ofdmInfo.SampleRate == cfg.sampleRate, 'Sample-rate mismatch.');

phy = wlanNonHTConfig('ChannelBandwidth', cfg.channelBandwidth);
cfg.txLLTF = wlanLLTF(phy);
cfg.lltfLength = numel(cfg.txLLTF);
cfg.lltfCPLength = cfg.lltfLength - 2*cfg.nFFT;
assert(cfg.lltfLength == 160 && cfg.lltfCPLength == 32, ...
    'Unexpected L-LTF length.');
ref = wlanLLTFDemodulate(cfg.txLLTF, cfg.channelBandwidth, 1);
cfg.lltfReference = mean(ref, 2);
cfg.lltfReference = cfg.lltfReference(:);
cfg.nLLTFInput = 4*cfg.nFFT;
cfg.nDataInput = 2*cfg.nFFT*cfg.numDataSymbols;
cfg.nX = double(cfg.includeLLTF)*cfg.nLLTFInput + cfg.nDataInput;
cfg.nY = 2*cfg.numActive*cfg.numDataSymbols;
assert(ismember(cfg.nX, [128 384]) && cfg.nY == 104, ...
    'Unexpected input/target width.');
if strcmp(cfg.labelMode, 'channel') && ~cfg.includeLLTF
    fprintf('[warning] Channel-label mode with X128 has no L-LTF input; consider cfg.includeLLTF=true.\n');
end

if cfg.smokeTest
    cfg.outputFolder = [cfg.outputFolder '_smoke'];
    cfg.trainPerCondition = 2;
    cfg.valPerCondition = 2;
    cfg.testPerCondition = 2;
    cfg.berPerCondition = 2;
    cfg.berOutputFolder = [cfg.berOutputFolder '_smoke'];
end
validateConditionSeeds(cfg);
runSelfTests(cfg);
if cfg.selfTestOnly
    fprintf('Self-tests passed. Dataset generation skipped.\n');
    return;
end

% Each output family is resolved separately. Existing training files are
% never inspected or modified in BER-only mode.
requestedTrainDir = fullfile(rootDir, cfg.outputFolder);
requestedBERDir = fullfile(rootDir, cfg.berOutputFolder);
assert(~strcmpi(requestedTrainDir, requestedBERDir), ...
    'Training and BER output folder names must be different.');

fprintf('Options: labelMode=%s, train/val/test=%d, BER=%d, X=%d, Y=%d, bits=%d\n', ...
    cfg.labelMode, cfg.generateTrainValTest, cfg.generateBER, cfg.nX, cfg.nY, cfg.nBits);
fprintf('Common TRAIN/VAL/TEST SNR grid (dB): %s\n', mat2str(cfg.snr));
fprintf('TRAIN/VAL/TEST: one shuffled X/Y pair per split, mixing all channels/SNRs.\n');
fprintf('BER SNR grid (dB): %s; files remain per channel/SNR.\n', mat2str(cfg.snrBER));

outDir = requestedTrainDir;
doTrain = cfg.generateTrainValTest;
if doTrain
    [outDir, doTrain] = resolveTrainOutput(requestedTrainDir, ...
        requestedBERDir, cfg);
else
    fprintf('[preserve] Existing training/validation/test data untouched: %s\n', ...
        requestedTrainDir);
end

berDir = requestedBERDir;
if cfg.generateBER
    berDir = resolveBEROutput(requestedBERDir, ...
        requestedTrainDir, outDir, cfg);
end

if doTrain
    completeFile = beginOutputFolder(outDir, 'DATASET_COMPLETE.txt');
    writeDatasetInfo(outDir, cfg, 'train_val_test');
    writeConstellationTable(outDir, cfg);
    fprintf('Training/test dataset directory: %s\n', outDir);
    fprintf('X=%d, Y=%d; includeLLTF=%d\n', cfg.nX, cfg.nY, cfg.includeLLTF);

    %% Train: a single mixed-SNR dataset; one balanced grid and one shuffle.
    data = generateGrid(cfg, cfg.snr, cfg.trainPerCondition, ...
        cfg.seed + 1000000, 'train');
    writeDataset(outDir, 'train', '', data, cfg.seed + 3000, cfg);
    clear data;

    %% Validation: the same SNR grid, with separate condition seeds.
    data = generateGrid(cfg, cfg.snr, cfg.valPerCondition, ...
        cfg.seed + 3000000, 'val');
    writeDataset(outDir, 'val', '', data, cfg.seed + 7000, cfg);
    clear data;

    %% Test: one mixed file pair, rather than channel/SNR-specific files.
    data = generateGrid(cfg, cfg.snr, cfg.testPerCondition, ...
        cfg.seed + 5000000, 'test');
    writeDataset(outDir, 'test', '', data, cfg.seed + 11000, cfg);
    clear data;
    writeManifest(completeFile, cfg);
end

%% BER: fresh random seeds; no reuse of training, validation, or test rows.
if cfg.generateBER
    completeBER = beginOutputFolder(berDir, 'BER_DATASET_COMPLETE.txt');
    writeDatasetInfo(berDir, cfg, 'ber');
    writeConstellationTable(berDir, cfg);
    fprintf('BER dataset directory: %s\n', berDir);
    fprintf('BER X=%d, Y=%d, bits=%d; rows/condition=%d\n', ...
        cfg.nX, cfg.nY, cfg.nBits, cfg.berPerCondition);
    for channelIndex = 1:numel(cfg.channels)
        for snrIndex = 1:numel(cfg.snrBER)
            snrDb = cfg.snrBER(snrIndex);
            seed = cfg.seed + cfg.berSeedOffset + ...
                10000*channelIndex + 100*snrIndex;
            data = generateCondition(cfg, channelIndex, snrDb, ...
                cfg.berPerCondition, seed, true);
            suffix = sprintf('_%s_%ddb', char(cfg.channelKeys(channelIndex)), snrDb);
            writeDataset(berDir, 'ber', suffix, data, [], cfg);
        end
    end
    clear data;
    writeBERManifest(completeBER, cfg);
end
fprintf('Done. All selected dataset families have completion markers.\n');

%% Local functions
function data = emptyDataset(cfg, n, saveBits)
    if nargin < 3
        saveBits = false;
    end
    data.x = zeros(n, cfg.nX, 'single');
    data.y = zeros(n, cfg.nY, 'single');
    if saveBits
        data.bits = zeros(n, cfg.nBits, 'uint8');
        % In channel mode, BER also saves known TX QAM, allowing independent
        % verification of the bit labels (H itself cannot be hard-decoded).
        if strcmp(cfg.labelMode, 'channel')
            data.tx = zeros(n, cfg.nY, 'single');
        end
    end
    if cfg.saveMeta
        data.channel_id = zeros(n,1,'uint8');
        data.snr_db = zeros(n,1);
    end
end

function data = generateGrid(cfg, snrs, nPerCondition, seed, tag)
    total = numel(cfg.channels)*numel(snrs)*nPerCondition;
    data = emptyDataset(cfg, total);
    names = fieldnames(data);
    row = 0;
    for channelIndex = 1:numel(cfg.channels)
        for snrIndex = 1:numel(snrs)
            conditionSeed = seed + 10000*channelIndex + 100*snrIndex;
            part = generateCondition(cfg, channelIndex, snrs(snrIndex), ...
                nPerCondition, conditionSeed);
            rows = row + (1:nPerCondition);
            for f = 1:numel(names)
                name = names{f};
                data.(name)(rows,:) = part.(name);
            end
            row = row + nPerCondition;
            fprintf('[%s] %s %3d dB: %d/%d rows\n', tag, ...
                char(cfg.channelKeys(channelIndex)), snrs(snrIndex), row, total);
        end
    end
    assert(row == total && size(data.x,1) == total && size(data.y,1) == total, ...
        'Mixed split row count mismatch.');
    if cfg.saveMeta
        assert(numel(data.channel_id) == total && numel(data.snr_db) == total, ...
            'Mixed split metadata row count mismatch.');
        for channelIndex = 1:numel(cfg.channels)
            for snrIndex = 1:numel(snrs)
                count = sum(data.channel_id == channelIndex & ...
                    data.snr_db == snrs(snrIndex));
                assert(count == nPerCondition, ...
                    'Mixed split has an unbalanced channel/SNR condition.');
            end
        end
    end
end

function data = generateCondition(cfg, channelIndex, snrDb, nRows, seed, saveBits)
    if nargin < 6
        saveBits = false;
    end
    rng(seed, 'twister');
    profile = cfg.channels(channelIndex);
    tgn = wlanTGnChannel( ...
        'SampleRate', cfg.sampleRate, ...
        'DelayProfile', char(profile), ...
        'CarrierFrequency', cfg.carrierFrequency, ...
        'EnvironmentalSpeed', cfg.environmentalSpeedKmh, ...
        'NumTransmitAntennas', 1, 'NumReceiveAntennas', 1, ...
        'LargeScaleFadingEffect', 'None', ...
        'NormalizePathGains', true, 'NormalizeChannelOutputs', true, ...
        'RandomStream', 'Global stream');
    if profile == "Model-D" || profile == "Model-E"
        tgn.FluorescentEffect = false;
    end
    cleanup = onCleanup(@() release(tgn));
    data = emptyDataset(cfg, nRows, saveBits);
    if cfg.saveMeta
        data.channel_id(:) = channelIndex;
        data.snr_db(:) = snrDb;
    end

    for n = 1:nRows
        bits = randi([0 1], cfg.numData*cfg.numBPSCS, cfg.numDataSymbols);
        txConstellation = wlanConstellationMap(bits, cfg.numBPSCS);
        % Use the SAME pilots for the transmitted waveform and ground truth.
        txActive = assembleActiveTones(txConstellation, cfg.txPilots, cfg);
        txData = modulateData(txConstellation, cfg);
        txBurst = [cfg.txLLTF; txData];
        paddedTx = [txBurst; complex(zeros(cfg.tailZeros,1))];

        % The global RNG is not rewound by reset; reset once per whole burst.
        reset(tgn);
        cleanRx = tgn(paddedTx);
        cleanBurst = alignBurst(cleanRx, cfg.txLLTF, ...
            cfg.maxSyncOffset, numel(txBurst));
        cleanLLTF = cleanBurst(1:cfg.lltfLength);
        usefulLLTF = cleanLLTF(cfg.lltfCPLength+1:end);
        signalPower = mean(abs(usefulLLTF).^2);
        assert(isfinite(signalPower) && signalPower > 0, ...
            'Nonpositive/invalid received L-LTF power.');
        noiseVariance = signalPower / 10^(snrDb/10);
        noise = sqrt(noiseVariance/2) * ...
            (randn(size(cleanBurst)) + 1i*randn(size(cleanBurst)));
        noisyBurst = cleanBurst + noise;
        noisyLLTF = noisyBurst(1:cfg.lltfLength);
        receivedData = noisyBurst(cfg.lltfLength+1:end);
        dataBlocks = reshape(receivedData, ...
            cfg.nFFT+cfg.cpLength, cfg.numDataSymbols);
        usefulData = dataBlocks(cfg.cpLength+1:end,:);

        data.x(n,:) = packInput(noisyLLTF, usefulData, cfg);
        if strcmp(cfg.labelMode, 'channel')
            % Reference H[k] for 52 active tones, from noiseless received L-LTF.
            % No AWGN enters the label; the same physical-channel realization
            % is used for the L-LTF and the subsequent received DATA symbol.
            % This is a clean-L-LTF channel estimate, not channel-object CSI.
            hRef = channelReference(cleanLLTF, cfg);
            assert(numel(hRef) == cfg.numActive && all(isfinite(hRef)), ...
                'Invalid clean L-LTF channel reference.');
            data.y(n,:) = packComplex(hRef);
        else
            data.y(n,:) = packComplex(txActive);
        end
        if saveBits
            % DATA-only mapper-input bit stream; pilots are excluded.
            data.bits(n,:) = uint8(bits(:).');
            if strcmp(cfg.labelMode, 'channel')
                data.tx(n,:) = packComplex(txActive);
            end
        end
    end
    clear cleanup;
end

function waveform = modulateData(symbols, cfg)
    waveform = cfg.fftGain * ofdmmod(symbols, cfg.nFFT, cfg.cpLength, ...
        cfg.nullFFTIndices, cfg.pilotFFTIndices, cfg.txPilots);
end

function active = assembleActiveTones(dataSymbols, pilotSymbols, cfg)
    assert(isequal(size(dataSymbols), [cfg.numData cfg.numDataSymbols]), ...
        'Unexpected DATA constellation dimensions.');
    assert(isequal(size(pilotSymbols), [cfg.numPilots cfg.numDataSymbols]), ...
        'Unexpected pilot constellation dimensions.');
    active = zeros(cfg.numActive, cfg.numDataSymbols, 'like', dataSymbols);
    active(cfg.dataIndices,:) = dataSymbols;
    active(cfg.pilotIndices,:) = pilotSymbols;
end

function symbols = demodulateData(waveform, cfg)
    % Extract ACTUAL received pilots, not the known transmitted pilot values.
    [dataSymbols, pilotSymbols] = ofdmdemod(waveform, cfg.nFFT, ...
        cfg.cpLength, cfg.cpLength, cfg.nullFFTIndices, cfg.pilotFFTIndices);
    symbols = assembleActiveTones(dataSymbols, pilotSymbols, cfg) / cfg.fftGain;
end

function h = channelReference(cleanLLTF, cfg)
    % Offset=1 uses the same useful L-LTF samples as the original X packing.
    demodulated = wlanLLTFDemodulate(cleanLLTF, cfg.channelBandwidth, 1);
    h = wlanLLTFChannelEstimate(demodulated, cfg.channelBandwidth);
    h = h(:);
end

function row = packInput(receivedLLTF, usefulData, cfg)
    lltfPart = packComplex(receivedLLTF(cfg.lltfCPLength+1:end));
    dataPart = packComplex(usefulData);
    if cfg.includeLLTF
        row = [lltfPart dataPart];
    else
        row = dataPart;
    end
    assert(numel(row) == cfg.nX, 'Unexpected real input width.');
end

function row = packComplex(z)
    z = z(:);
    row = single([real(z).' imag(z).']);
end

function aligned = alignBurst(rx, txLLTF, maxOffset, burstLength)
    nLTF = numel(txLLTF);
    maxStart = min(maxOffset+1, numel(rx)-burstLength+1);
    assert(maxStart >= 1, 'Insufficient received samples for alignment.');
    metric = zeros(maxStart,1);
    for first = 1:maxStart
        metric(first) = abs(txLLTF' * rx(first:first+nLTF-1));
    end
    [~, first] = max(metric);
    aligned = rx(first:first+burstLength-1);
end

function writeDataset(outDir, prefix, suffix, data, shuffleSeed, cfg)
    n = size(data.x,1);
    assert(isequal(size(data.x), [n cfg.nX]), 'Invalid X dimensions.');
    assert(isequal(size(data.y), [n cfg.nY]), 'Invalid Y dimensions.');
    order = (1:n).';
    if ~isempty(shuffleSeed)
        rng(shuffleSeed, 'twister');
        order = randperm(n).';
    end
    names = {'x','y'};
    if isfield(data, 'bits')
        verifyBERLabels(data, cfg);
        names{end+1} = 'bits';
        if isfield(data, 'tx')
            names{end+1} = 'tx';  % channel mode only, known transmitted QAM
        end
    end
    for k = 1:numel(names)
        name = names{k};
        value = data.(name)(order,:);
        assert(all(isfinite(value(:))), 'Nonfinite entries in %s.', name);
        writematrix(value, fullfile(outDir, [prefix '_' name suffix '.csv']));
    end

    metaPath = fullfile(outDir, [prefix '_meta' suffix '.csv']);
    if cfg.saveMeta && ~strcmp(prefix, 'ber')
        channel = cfg.channelKeys(double(data.channel_id(order)));
        channel = channel(:);
        snr_db = data.snr_db(order);
        snr_db = snr_db(:);
        assert(numel(channel) == n && numel(snr_db) == n, ...
            'Metadata row mismatch.');
        % Force ALL table variables to N-by-1, including N=1.
        writetable(table(channel, snr_db), metaPath);
    elseif cfg.overwriteExisting && exist(metaPath, 'file')
        % Remove only this known stale optional output, not arbitrary files.
        delete(metaPath);
    end
    fprintf('[write] %s%s: %d synchronized %s rows\n', ...
        prefix, suffix, n, strjoin(names, '/'));
end

function writeDatasetInfo(outDir, cfg, datasetFamily)
    info.schema = sprintf('ofdm_64qam_x%d_y104_%s_mixed_v6', cfg.nX, cfg.labelMode);
    info.dataset_family = datasetFamily;
    info.generator_version = cfg.generatorVersion;
    if strcmp(datasetFamily, 'ber')
        info.schema = sprintf('ofdm_64qam_x%d_y104_%s_ber_v5', cfg.nX, cfg.labelMode);
        info.available_splits = {'ber'};
    else
        info.available_splits = {'train','val','test'};
    end
    info.label_mode = cfg.labelMode;
    info.channel_label_reference = 'CLEAN received L-LTF demodulation + wlanLLTFChannelEstimate (52 active tones)';
    info.channel_label_caveat = 'Noiseless L-LTF-based frequency-response reference; not instantaneous path-gain CSI at DATA time';
    info.ber_tx_qam_saved = strcmp(datasetFamily, 'ber') && strcmp(cfg.labelMode, 'channel');
    info.modulation_order = cfg.modulationOrder;
    info.num_data_symbols = cfg.numDataSymbols;
    info.input_columns = cfg.nX;
    info.target_columns = cfg.nY;
    info.include_lltf = cfg.includeLLTF;
    info.input_normalization = 'none after channel/noise; original OFDM and channel settings retained';
    if cfg.includeLLTF
        info.input_layout = '[Re(LTF1),Re(LTF2),Im(LTF1),Im(LTF2),Re(DATA),Im(DATA)]';
        info.input_slices_python.lltf_real = [0 128];
        info.input_slices_python.lltf_imag = [128 256];
        info.input_slices_python.data_real = [256 320];
        info.input_slices_python.data_imag = [320 384];
    else
        info.input_layout = '[Re(DATA64),Im(DATA64)]';
        info.input_slices_python.data_real = [0 64];
        info.input_slices_python.data_imag = [64 128];
    end
    info.constellation_mapping_file = 'qam64_mapping.csv';
    if strcmp(cfg.labelMode, 'channel')
        info.target_normalization = 'none; physical complex H from noise-free L-LTF';
        info.target_layout = '[Re(H_active52),Im(H_active52)]';
        info.target_definition = 'channel reference H(k) obtained from noiseless L-LTF of same burst';
    else
        info.target_normalization = 'original wlanConstellationMap values; no per-row normalization';
        info.target_layout = '[Re(TX_active52),Im(TX_active52)]';
        info.target_definition = 'transmitted QAM DATA symbols and 4 fixed pilots';
    end
    info.target_is_channel = strcmp(cfg.labelMode, 'channel');
    info.target_is_spike_count = false;
    info.active_frequency_indices = cfg.activeFrequencyIndices(:).';
    info.active_fft_indices_matlab = cfg.activeFFTIndices(:).';
    info.data_active_indices_python = (cfg.dataIndices(:)-1).';
    info.pilot_active_indices_python = (cfg.pilotIndices(:)-1).';
    info.pilot_real = real(cfg.txPilots(:)).';
    info.pilot_imag = imag(cfg.txPilots(:)).';
    info.lltf_reference_real = real(cfg.lltfReference(:)).';
    info.lltf_reference_imag = imag(cfg.lltfReference(:)).';
    info.fft_length = cfg.nFFT;
    info.cp_length = cfg.cpLength;
    info.fft_gain = cfg.fftGain;
    info.sample_rate = cfg.sampleRate;
    info.carrier_frequency = cfg.carrierFrequency;
    info.environmental_speed_kmh = cfg.environmentalSpeedKmh;
    info.seed = cfg.seed;
    info.channel_keys = cellstr(cfg.channelKeys(:));
    info.channel_profiles = cellstr(cfg.channels(:));
    info.snr_train = cfg.snr;
    info.snr_validation = cfg.snr;
    info.snr_test = cfg.snr;
    info.train_val_test_storage = 'one shuffled X/Y pair per split; all channels and SNRs pooled';
    info.train_val_test_file_pattern = '{train,val,test}_{x,y}.csv';
    info.train_val_test_meta_file_pattern = '{train,val,test}_meta.csv';
    info.condition_sampling = 'same row count for every channel/SNR condition within each split';
    info.rows_shuffled = ~strcmp(datasetFamily, 'ber');
    info.split_seed_offsets = struct('train', 1000000, 'val', 3000000, ...
        'test', 5000000, 'ber', cfg.berSeedOffset);
    info.split_shuffle_seed_offsets = struct('train', 3000, 'val', 7000, 'test', 11000);
    info.snr_ber = cfg.snrBER;
    info.ber_rows_per_condition = cfg.berPerCondition;
    info.bits_per_row = cfg.nBits;
    info.bits_per_data_subcarrier = cfg.numBPSCS;
    info.bits_saved_for_ber = strcmp(datasetFamily, 'ber');
    info.bits_layout = 'DATA tone 1: b0...b5, DATA tone 2: b0...b5, ..., DATA tone 48';
    info.ber_scope = 'uncoded mapper-input DATA-bit BER; exclude all pilots';
    info.ber_seed_offset = cfg.berSeedOffset;
    info.condition_seed_rule = 'seed + split_offset + 10000*channel_index + 100*snr_index (1-based)';
    info.ber_file_pattern = 'ber_{x,y,bits}_<channel_key>_<integer_snr>db.csv';
    info.ber_tx_file_pattern = 'ber_tx_<channel_key>_<integer_snr>db.csv (channel mode only)';
    info.csv_header_for_x_y_bits = false;
    info.row_alignment = 'Within a split or BER condition, row n in x/y/optional bits/tx/meta is the same OFDM symbol';
    info.prediction_layout_for_ber = info.target_layout;
    if strcmp(cfg.labelMode, 'channel')
        info.ber_decoding = 'FFT of received useful DATA from X, divide by predicted complex H, then 64-QAM hard decision';
    else
        info.ber_decoding = '64-QAM hard decision on predicted transmitted DATA points';
    end
    info.completion_marker = 'DATASET_COMPLETE.txt';
    if strcmp(datasetFamily, 'ber')
        info.completion_marker = 'BER_DATASET_COMPLETE.txt';
    end
    info.train_rows_per_condition = cfg.trainPerCondition;
    info.val_rows_per_condition = cfg.valPerCondition;
    info.test_rows_per_condition = cfg.testPerCondition;
    info.train_rows = numel(cfg.channels)*numel(cfg.snr)*cfg.trainPerCondition;
    info.val_rows = numel(cfg.channels)*numel(cfg.snr)*cfg.valPerCondition;
    info.test_rows = numel(cfg.channels)*numel(cfg.snr)*cfg.testPerCondition;
    info.meta_saved_for_train_validation = cfg.saveMeta && ~strcmp(datasetFamily, 'ber');
    info.meta_columns = {'channel','snr_db'};
    info.meta_row_alignment = 'same permutation as X and Y; metadata is not model input';
    info.test_meta_saved = cfg.saveMeta && ~strcmp(datasetFamily, 'ber');
    info.ber_meta_saved = false;
    info.scope = 'uncoded L-LTF+DATA; fixed pilots; CLEAN-LTF timing';
    info.snr_definition = 'received useful clean L-LTF power / time noise variance';
    info.loss = 'mean squared complex distance over all 52 complex target tones';
    % JSON replaces the unused table-based sidecar that failed for K=1.
    fid = fopen(fullfile(outDir, 'dataset_info.json'), 'w');
    assert(fid >= 0, 'Could not create dataset_info.json.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(info));
    clear cleanup;
end

function writeManifest(path, cfg)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Could not create DATASET_COMPLETE.txt.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'schema: ofdm_64qam_x%d_y104_%s_mixed_v6\n', cfg.nX, cfg.labelMode);
    fprintf(fid, 'status: all requested dataset splits finished\n');
    fprintf(fid, 'x columns: %d; y columns: %d\n', cfg.nX, cfg.nY);
    fprintf(fid, 'label mode: %s\n', cfg.labelMode);
    if strcmp(cfg.labelMode, 'channel')
        fprintf(fid, 'y: 52 complex H from CLEAN received L-LTF\n');
    else
        fprintf(fid, 'y: transmitted 64-QAM DATA and 4 fixed pilots\n');
    end
    fprintf(fid, 'Y is physical I/Q; the learner performs count decoding internally\n');
    fprintf(fid, 'storage: one shuffled X/Y pair per train/val/test split\n');
    fprintf(fid, 'SNR grid shared by train/val/test (dB): %s\n', mat2str(cfg.snr));
    fprintf(fid, 'conditions per split: %d\n', numel(cfg.channels)*numel(cfg.snr));
    fprintf(fid, 'optional train/validation/test metadata: %d\n', cfg.saveMeta);
    fprintf(fid, 'train rows: %d\n', ...
        numel(cfg.channels)*numel(cfg.snr)*cfg.trainPerCondition);
    fprintf(fid, 'validation rows: %d\n', ...
        numel(cfg.channels)*numel(cfg.snr)*cfg.valPerCondition);
    fprintf(fid, 'test rows: %d\n', ...
        numel(cfg.channels)*numel(cfg.snr)*cfg.testPerCondition);
    fprintf(fid, 'train files: train_x.csv, train_y.csv\n');
    fprintf(fid, 'validation files: val_x.csv, val_y.csv\n');
    fprintf(fid, 'test files: test_x.csv, test_y.csv\n');
    fprintf(fid, 'metadata rows are shuffled with the same permutation as X/Y\n');
    fprintf(fid, 'complex MSE = 2 * packed-real elementwise MSE\n');
    fprintf(fid, 'layout and simulation settings: dataset_info.json\n');
    clear cleanup;
end

function runSelfTests(cfg)
    previousRng = rng;
    cleanup = onCleanup(@() rng(previousRng));
    rng(cfg.seed, 'twister');
    tolerance = 1e-10;
    identityH = channelReference(cfg.txLLTF, cfg);
    assert(max(abs(identityH-1)) < tolerance, ...
        'Standard L-LTF identity-channel check failed.');

    % Check the amplitude convention against the standard WLAN demodulator.
    rawLTF = ofdmdemod(cfg.txLLTF(cfg.lltfCPLength+1:end), ...
        cfg.nFFT, 0, 0, cfg.nullFFTIndices) / cfg.fftGain;
    standardLTF = wlanLLTFDemodulate(cfg.txLLTF, cfg.channelBandwidth, 1);
    assert(max(abs(rawLTF(:)-standardLTF(:))) < tolerance, ...
        'OFDM/WLAN normalization or tone-order mismatch.');

    bits = randi([0 1], cfg.numData*cfg.numBPSCS, cfg.numDataSymbols);
    dataTarget = wlanConstellationMap(bits, cfg.numBPSCS);
    target = assembleActiveTones(dataTarget, cfg.txPilots, cfg);
    txData = modulateData(dataTarget, cfg);
    recovered = demodulateData(txData, cfg);
    assert(max(abs(recovered(:)-target(:))) < tolerance, ...
        'No-channel 52-tone OFDM constellation round trip failed.');
    packedTarget = packComplex(target);
    assert(numel(packedTarget) == cfg.nY, 'Target packing mismatch.');
    assert(cfg.nY == 104*cfg.numDataSymbols, ...
        'Expected 104 real target columns per OFDM symbol.');
    assert(isequal(target(cfg.dataIndices,:), dataTarget), ...
        'DATA insertion into active-tone target failed.');
    assert(isequal(target(cfg.pilotIndices,:), cfg.txPilots), ...
        'Pilot insertion into active-tone target failed.');
    unpacked = reshape(complex(double(packedTarget(1:cfg.nY/2)), ...
        double(packedTarget(cfg.nY/2+1:end))), ...
        cfg.numActive, cfg.numDataSymbols);
    assert(max(abs(unpacked(:)-target(:))) < 2*eps('single'), ...
        'Real/imag packing order mismatch.');

    % A received pilot must retain channel distortion, not be replaced by tx.
    gain = 0.6+0.35i;
    gained = demodulateData(gain*txData, cfg);
    gainedPilots = gained(cfg.pilotIndices,:);
    assert(max(abs(gainedPilots(:)-gain*cfg.txPilots(:))) < tolerance, ...
        'Received pilots were lost or replaced by transmitted pilots.');

    % Verify the all-tone complex-MSE and packed-real-MSE factor of two.
    probeError = reshape(1:cfg.nY/2, cfg.numActive, ...
        cfg.numDataSymbols)/cfg.nY + 0.25i;
    packedError = double(packComplex(probeError));
    complexMSE = mean(abs(probeError(:)).^2);
    realMSE = mean(packedError.^2);
    assert(abs(complexMSE-2*realMSE) < 2*eps('single'), ...
        'Complex-MSE / real-MSE scaling check failed.');

    % Verify that the time-domain DATA inside X reproduces all active tones.
    blocks = reshape(txData, cfg.nFFT+cfg.cpLength, cfg.numDataSymbols);
    useful = blocks(cfg.cpLength+1:end,:);
    % Omitting pilotidx keeps all non-null tones, an independent order check.
    fromRaw = ofdmdemod(useful(:), cfg.nFFT, 0, 0, ...
        cfg.nullFFTIndices) / cfg.fftGain;
    assert(max(abs(fromRaw(:)-target(:))) < tolerance, ...
        'Raw DATA and frequency DATA packing disagree.');

    % A deterministic short multipath channel tests LTF/DATA compatibility.
    txBurst = [cfg.txLLTF; txData];
    taps = [0.9+0.2i; 0.15-0.08i; 0.06+0.02i];
    clean = filter(taps, 1, txBurst);
    h = channelReference(clean(1:cfg.lltfLength), cfg);
    dataFreq = demodulateData(clean(cfg.lltfLength+1:end), cfg);
    equalized = bsxfun(@rdivide, dataFreq, h);
    assert(max(abs(equalized(:)-target(:))) < tolerance, ...
        'Multipath L-LTF/DATA equalization check failed.');

    inputRow = packInput(cfg.txLLTF, useful, cfg);
    assert(isequal(size(inputRow), [1 cfg.nX]), 'Input width mismatch.');
    if cfg.includeLLTF
        assert(isequal(inputRow(1:256), ...
            packComplex(cfg.txLLTF(cfg.lltfCPLength+1:end))), ...
            'L-LTF input layout changed.');
    end
    dataPart = inputRow(end-127:end);
    assert(isequal(dataPart, packComplex(useful)), ...
        'Received DATA is missing from X.');
    inputData = complex(double(dataPart(1:64)), ...
        double(dataPart(65:128))).';
    inputTones = ofdmdemod(inputData, cfg.nFFT, 0, 0, ...
        cfg.nullFFTIndices) / cfg.fftGain;
    assert(max(abs(inputTones(:)-target(:))) < 2e-6, ...
        'Saved X DATA coordinates cannot reproduce target tones.');

    % Test the only remaining table schema for both one row and several rows.
    for n = [1 3]
        channel = repmat(cfg.channelKeys(1), n, 1);
        snr_db = zeros(n,1);
        t = table(channel(:), snr_db(:), ...
            'VariableNames', {'channel','snr_db'});
        assert(height(t) == n && width(t) == 2, 'Metadata table shape failed.');
    end

    words = dec2bin((0:cfg.modulationOrder-1).', cfg.numBPSCS)-'0';
    reference = wlanConstellationMap(reshape(words.',[],1), cfg.numBPSCS);
    assert(abs(mean(abs(reference).^2)-1) < tolerance, ...
        'Unexpected constellation normalization.');
    expectedLevels = (-7:2:7).'/sqrt(42);
    assert(max(abs(sort(unique(real(reference(:))))-expectedLevels)) < tolerance, ...
        'Unexpected 64-QAM real-coordinate levels.');
    assert(max(abs(sort(unique(imag(reference(:))))-expectedLevels)) < tolerance, ...
        'Unexpected 64-QAM imaginary-coordinate levels.');
    % End-to-end label test: packed physical I/Q -> DATA -> mapper bits.
    recoveredData = unpacked(cfg.dataIndices,:);
    distances = abs(bsxfun(@minus, recoveredData(:), reference(:).')).^2;
    [~, nearest] = min(distances, [], 2);
    decodedBits = reshape(words(nearest,:).', 1, []);
    assert(isequal(decodedBits, double(bits(:).')), ...
        'BER hard-decision bit order or pilot exclusion failed.');
    [~, nearestAll] = min(abs(bsxfun(@minus, reference(:), reference(:).')).^2, [], 2);
    assert(isequal(words(nearestAll,:), words), '64-point mapping bijection failed.');
    for n = [1 3]
        probe = emptyDataset(cfg, n, true);
        if strcmp(cfg.labelMode, 'channel')
            probe.y = repmat(packComplex(h), n, 1);
            probe.tx = repmat(packedTarget, n, 1);
        else
            probe.y = repmat(packedTarget, n, 1);
        end
        probe.bits = repmat(uint8(bits(:).'), n, 1);
        verifyBERLabels(probe, cfg);
    end
    fprintf(['Self-tests: standard mapping, OFDM, pilots, X=%d, Y=104, ' ...
        'metadata shapes, MSE, multipath, BER bit round trip OK (mode=%s).\n'], cfg.nX, cfg.labelMode);
    clear cleanup;
end


function writeConstellationTable(outDir, cfg)
    % Export the actual MATLAB bit mapping, rather than guessing the bit order in the learner.
    words = dec2bin((0:cfg.modulationOrder-1).', cfg.numBPSCS)-'0';
    symbols = wlanConstellationMap(reshape(words.',[],1), cfg.numBPSCS);
    values = [real(symbols(:)), imag(symbols(:)), words];
    names = {'real','imag','b0','b1','b2','b3','b4','b5'};
    writetable(array2table(values, 'VariableNames', names), ...
        fullfile(outDir, 'qam64_mapping.csv'));
end


function verifyBERLabels(data, cfg)
    % Verify EVERY row against the actual mapper bits, for both label modes.
    n = size(data.y,1);
    assert(isequal(size(data.bits), [n cfg.nBits]), 'Invalid BER bit dimensions.');
    assert(all(data.bits(:) == 0 | data.bits(:) == 1), 'BER bits must be binary.');
    assert(cfg.numDataSymbols == 1, 'BER CSV layout requires one DATA symbol.');
    if strcmp(cfg.labelMode, 'channel')
        assert(isfield(data, 'tx') && isequal(size(data.tx), [n cfg.nY]), ...
            'BER channel mode requires a matching transmitted QAM reference.');
        reference = data.tx;
    else
        reference = data.y;
    end
    symbols = wlanConstellationMap(double(data.bits.'), cfg.numBPSCS).';
    fromTX = complex(double(reference(:,cfg.dataIndices)), ...
        double(reference(:,cfg.numActive+cfg.dataIndices)));
    assert(max(abs(symbols(:)-fromTX(:))) < 2*eps('single'), ...
        'BER transmitted-symbol / bit label mismatch.');
    if strcmp(cfg.labelMode, 'channel')
        h = complex(double(data.y(:,1:cfg.numActive)), ...
            double(data.y(:,cfg.numActive+1:end)));
        assert(all(isfinite(h(:))), 'BER channel labels must be finite.');
    end
end

function validateOutputName(folderName)
    % Output names must be direct child folders of this script's directory.
    assert(ischar(folderName) && isrow(folderName) && ~isempty(folderName), ...
        'Dataset folder names must be nonempty character vectors.');
    assert(~strcmp(folderName, '.') && ~strcmp(folderName, '..') && ...
        isempty(regexp(folderName, '[\\/:*?"<>|]', 'once')) && ...
        folderName(end) ~= '.' && folderName(end) ~= ' ', ...
        'Output folder must be a single folder name, e.g. dataset_ber.');
end

function occupied = outputIsOccupied(path)
    if exist(path, 'dir') ~= 0
        contents = dir(path);
        contents = contents(~ismember({contents.name}, {'.','..'}));
        occupied = ~isempty(contents);
    else
        assert(exist(path, 'file') == 0, ...
            'Output folder conflicts with a regular file: %s', path);
        occupied = false;
    end
end

function newDir = unusedOutputFolder(requestedDir, protectedDirs)
    % Find a new, unused name without touching an existing directory.
    for suffix = 1:99999
        candidate = sprintf('%s_%03d', requestedDir, suffix);
        if exist(candidate, 'dir') == 0 && exist(candidate, 'file') == 0 && ...
                ~any(strcmpi(candidate, protectedDirs))
            newDir = candidate;
            return;
        end
    end
    error('gendata:NoFreeFolder', ...
        'Could not find an unused output directory for %s', requestedDir);
end

function [outDir, generateTrain] = resolveTrainOutput(trainDir, berDir, cfg)
    outDir = trainDir;
    generateTrain = true;
    if ~outputIsOccupied(trainDir)
        return;
    end
    if cfg.overwriteExisting
        fprintf('[overwrite] Existing training output selected: %s\n', trainDir);
        return;
    end
    if strcmp(cfg.existingTrainPolicy, 'skip')
        generateTrain = false;
        fprintf('[preserve] Training folder already contains data; skipping generation: %s\n', trainDir);
        if exist(fullfile(trainDir, 'DATASET_COMPLETE.txt'), 'file') == 0
            fprintf('[warning] Training folder has no DATASET_COMPLETE.txt; verify its contents.\n');
        end
        return;
    end
    outDir = unusedOutputFolder(trainDir, {berDir});
    fprintf('[preserve] Existing training folder kept: %s\n', trainDir);
    fprintf('[new] Training output: %s\n', outDir);
end

function outDir = resolveBEROutput(berDir, trainDir, selectedTrainDir, cfg)
    outDir = berDir;
    if ~outputIsOccupied(berDir)
        return;
    end
    if cfg.overwriteExisting
        fprintf('[overwrite] Existing BER output selected: %s\n', berDir);
        return;
    end
    assert(cfg.autoNewBERFolder, ...
        'BER folder is occupied. Set cfg.autoNewBERFolder=true or use a fresh name.');
    outDir = unusedOutputFolder(berDir, {trainDir, selectedTrainDir});
    fprintf('[preserve] Existing BER folder kept: %s\n', berDir);
    fprintf('[new] BER output: %s\n', outDir);
end

function completeFile = beginOutputFolder(outDir, markerName)
    if ~exist(outDir, 'dir')
        [ok, message] = mkdir(outDir);
        assert(ok, 'Cannot create output folder: %s', message);
    end
    completeFile = fullfile(outDir, markerName);
    if exist(completeFile, 'file')
        delete(completeFile);
    end
end

function validateConditionSeeds(cfg)
    % Account for every current split, even during a BER-only run.
    % Reject accidental overlap after changing offsets or grid sizes.
    splitOffsets = [1000000 3000000 5000000 cfg.berSeedOffset];
    grids = {cfg.snr, cfg.snr, cfg.snr, cfg.snrBER};
    seeds = [];
    for f = 1:numel(splitOffsets)
        for c = 1:numel(cfg.channels)
            for s = 1:numel(grids{f})
                seeds(end+1) = cfg.seed + splitOffsets(f) + 10000*c + 100*s; %#ok<AGROW>
            end
        end
    end
    assert(all(seeds >= 0 & seeds <= 2^32-1), 'RNG seeds must be uint32-range integers.');
    assert(numel(unique(seeds)) == numel(seeds), ...
        'Condition RNG seed collision. Change cfg.berSeedOffset or reduce grid size.');
end

function writeBERManifest(path, cfg)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Could not create BER_DATASET_COMPLETE.txt.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'schema: ofdm_64qam_x%d_y104_%s_ber_v5\n', cfg.nX, cfg.labelMode);
    fprintf(fid, 'label mode: %s\n', cfg.labelMode);
    fprintf(fid, 'status: all requested BER channel/SNR conditions finished\n');
    fprintf(fid, 'x columns: %d; y columns: %d; bits columns: %d\n', ...
        cfg.nX, cfg.nY, cfg.nBits);
    fprintf(fid, 'rows per condition: %d\n', cfg.berPerCondition);
    fprintf(fid, 'DATA bits per condition: %.0f\n', cfg.berPerCondition*cfg.nBits);
    fprintf(fid, 'conditions: %d\n', numel(cfg.channels)*numel(cfg.snrBER));
    fprintf(fid, 'SNR grid (dB): %s\n', mat2str(cfg.snrBER));
    fprintf(fid, 'BER denominator: number of rows * 48 DATA tones * 6 bits\n');
    fprintf(fid, 'pilots excluded; uncoded mapper-input BER; CLEAN-LTF timing retained\n');
    if strcmp(cfg.labelMode, 'channel')
        fprintf(fid, 'bit labels remapped to ber_tx and checked for every saved BER row\n');
        fprintf(fid, 'prediction order: [Re(H52), Im(H52)]; equalize FFT(X_DATA) / H\n');
        fprintf(fid, 'ber_tx is transmitted QAM (not network supervision)\n');
    else
        fprintf(fid, 'bit labels remapped to Y and checked for every saved BER row\n');
        fprintf(fid, 'prediction order: [Re(TX52), Im(TX52)]\n');
    end
    fprintf(fid, 'mapping and layout: qam64_mapping.csv, dataset_info.json\n');
    clear cleanup;
end
