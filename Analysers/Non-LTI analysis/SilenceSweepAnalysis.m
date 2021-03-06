function OUT = SilenceSweepAnalysis(IN,octsmooth,thresholddB)
% Use this function to analyse recordings made using the
% SilenceSweep_Farina2009 test signal.
%
% For background information, see:
% A. Farina (2009) "Silence Sweep: a novel method for measuring
% electro-acoustical devices," 126th AES Convention, Munich, Germany
%
% It is best to analyse the actual recording, rather than convolving the
% recording with its inverse filter (audio2). The inverse filtering is done
% within this function (if it has not already been done).
%
% The following analyses are done, represented by five figures (charts).
% Fractional octave band smoothing can be applied (to the frequency domain
% analyses).
%
% 1. Signal, noise, and signal-to-noise ratio (SNR) of the recording, where
%    the recorded MLS is taken as signal, and the sound before it as the
%    noise. The analysis is done using a series of Hann windows, power
%    averaged. The window length is equal to half the MLS length.
%
% 2. Signal, noise, noise + distortion, SNR, and
%    signal-to-noise-and-distortion (SINAD) of the recording after convolution
%    with the inverse filter. Here the MLS is taken as the signal, the period
%    of silence just before the MLS (the 'gap' between the silence recording
%    and the MLS, which is at least 1 MLS cycle long) is taken as the noise,
%    and the 1-cycle interruption of the MLS is taken as the noise with
%    distortion. Note that, due to inverse filtering, the spectral slope of
%    signal and noise is changed by 3 dB/octave, compared to the first
%    analysis. SNR and SINAD are both displayed in dB, using positive values
%    (assuming signal is stronger than noise and distortion). Hence, if
%    distortion is significant, the SINAD curve should be lower than the SNR
%    curve. If the SINAD curve is higher than the SNR curve, that implies that
%    the background noise varied during the measurement.
%
% 3. Impulse response visualisation in the time domain, of the MLS signal
%    and the sweep. This includes the first four distortion pseudo-IRs from
%    the sweep. The effective noise floor is taken from equivalent time
%    intervals in the silence at the start of the recording (which was
%    convolved with the inverse filter).
%
% 4. Frequency domain visualisation of the MLS and sweep impulse responses
%    (including the first four distortion pseudo IRs). A window function is
%    applied prior to FFT, consisting of a Blackman-Harris window, the first
%    half of which has been raised to a power of 4. This asymmetric window
%    function assumes that most of the period before the expected IR arrival
%    time is noise. The effective noise floor is analysed the same way.
%
% 5. Frequency domain visualisation of the harmonic distortion relative to
%    the fundamental, as a function of excitation frequency. Only values that
%    are greater than a threshold relative to the effective noise floor are
%    shown. By default, this threshold is 0 dB, but arguably it should be
%    higher (you can change it in the dialog box or in the function call).
%
% You can assess the limits of these analyses by analysing the test signal
% itself (without playing it through the system). It is possible to change
% the sensitivity of the analysis by changing the test signal parameters
% (especially the fade-in and fade-out duration and the MLS order).
%
% Note that this function automatically time-aligns the recorded signal to
% the expected envelope (by cross-correlation), but this may fail in the
% unlikely event that there was a very long time mis-match. This function
% assumes that the recording is at least as long as the test signal, and it
% cannot analyse a shorter recording.
%
% Code by Densil Cabrera, December 2015


if ~isfield(IN,'properties')
    if nargin == 1
        warndlg('Required properties field is missing from the input audio. This analyser is designed to analyse recorded signals using the test signal generated by SilenceSweep_Farina2009. Unable to analyse.','SilenceSweepAnalysis','modal');
    end
    OUT = [];
    return
end

if ~isfield(IN.properties,'SilenceSweep')
    if nargin == 1
        warndlg('Required properties field is missing from the input audio. This analyser is designed to analyse recorded signals using the test signal generated by SilenceSweep_Farina2009. Unable to analyse.','SilenceSweepAnalysis','modal');
    end
    OUT = [];
    return
end

if nargin == 1
    param = inputdlg({'Fractional octave smoothing (use 0 for no smoothing, 3 for 1/3-octave smoothing, 1 for octave smoothing)';...
        'Threshold above background noise to display as distortion [dB]'},...
        'Silence Sweep Analysis',...
        [1 60],...
        {'0','0'});
    
    param = str2num(char(param));
    
    if length(param) < 2, param = []; end
    if ~isempty(param)
        octsmooth = param(1);
        thresholddB = param(2);
    else
        % get out of here if the user presses 'cancel'
        OUT = [];
        return
    end
end

DCCoupling = 0;
MLSlen = 2^IN.properties.MLSorder-1;
sweeplen = round(IN.properties.sweepdur * IN.fs);
gaplen = round(IN.properties.gapdur * IN.fs);
winlen = round(MLSlen/2);
wf = hann(winlen);
NOVERLAP = ceil(winlen/3);
fs = IN.fs;

[~,chans,bands,dim4,dim5,dim6] = size(IN.audio);

if bands > 1
    % sum multiple bands
    IN.audio = sum(IN.audio,3);
end


if dim4 > 1 % multicycle
    % this should not occur, unless the user has convolved with audio2
    % prior to calling this function
    if isfield(IN.properties,'relgain')
        if isinf(IN.properties.relgain(1))
            % discard silent cycle (it is redundant because the test signal
            % includes silence) & apply synchronous average
            IN.audio = mean(IN.audio(:,:,1,2:end,:,:),4);
        end
    else
        % synchronous average
        IN.audio = mean(IN.audio,4);
    end
end

if chans > 1
    if isfield(IN,'chanID')
        chanID = IN.chanID;
    else
        chanID = makechanID(chans,0);
    end
else
    chanID = {''};
end

if dim5 > 1
    if isfield(IN,'dim5ID')
        dim5ID = IN.dim5ID;
    else
        dim5ID = makechanID(dim5,10);
    end
else
    dim5ID = {''};
end

if dim6 > 1
    if isfield(IN,'dim6ID')
        dim6ID = IN.dim6ID;
    else
        dim6ID = makechanID(dim6,20);
    end
else
    dim6ID = {''};
end

linecolor = HSVplotcolours2(chans, 5, dim5); % H,S,V
% ANALYSE SNR, USING UNCONVOLVED RECORDING
if isfield(IN,'audio2') % this indicates that convolution has not been done
    noise = IN.audio(1:sweeplen,:,:,:,:,:); % should be safe unless there is negative latency
    signal = IN.audio(sweeplen+gaplen+2*MLSlen:sweeplen+gaplen+8*MLSlen+1,:,:,:,:,:); % allowing for latency issues
    [SigPow, NoisePow,SNR] = deal(zeros(floor(winlen/2),chans,dim5,dim6));
    for ch = 1:chans
        for d5 = 1:dim5
            for d6 = 1:dim6
                [~,f,~,P1] = spectrogram(noise(:,ch,1,1,d5,d6),wf,NOVERLAP,[],fs);
                [~,~,~,P2] = spectrogram(signal(:,ch,1,1,d5,d6),wf,NOVERLAP,[],fs);
                NoisePow(:,ch,d5,d6) = mean(P1(1:floor(winlen/2),:),2);
                SigPow(:,ch,d5,d6) = mean(P2(1:floor(winlen/2),:),2);
                SNR(:,ch,d5,d6) = SigPow(:,ch,d5,d6)./NoisePow(:,ch,d5,d6); % although this looks inefficient, it is done here to avoid smoothing artefacts
                if octsmooth > 0
                    NoisePow(:,ch,d5,d6) = octavesmoothing(NoisePow(:,ch,d5,d6),octsmooth, fs);
                    SigPow(:,ch,d5,d6) = octavesmoothing(SigPow(:,ch,d5,d6),octsmooth, fs);
                    SNR(:,ch,d5,d6) = octavesmoothing(SNR(:,ch,d5,d6),octsmooth, fs);
                end
            end
        end
    end
    clear signal noise P1 P2
    f=f(1:floor(winlen/2));
    if octsmooth > 0
        lowlimit = 128/(winlen/fs); % avoid very low freq hump error
        NoisePow = NoisePow(f>lowlimit,:,:,:,:,:);
        NoisePow(NoisePow<0)=0;
        SigPow = SigPow(f>lowlimit,:,:,:,:,:);
        SigPow(SigPow<0)=0;
        SNR = SNR(f>lowlimit,:,:,:,:,:);
        SNR(SNR<0)=0;
        f = f(f>lowlimit);
    end
    
    
    % Generate figure(s) for SNR analysis
    for d6 = 1:dim6
        figure('Name','SNR without inverse filtering');
        for ch = 1:chans
            for d5 = 1:dim5
                labelstring = [char(chanID(ch)), ' ', char(dim5ID(d5)), ' ' char(dim6ID(d6))];
                
                subplot(2,1,1) % plot of Signal and Noise spectra
                colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
                semilogx(f,10*log10(NoisePow(:,ch,d5,d6)),...
                    'color',colr,...
                    'DisplayName',['Noise ' labelstring]);
                hold on
                colr = permute(linecolor(ch,3,d5,:),[1,4,2,3]);
                semilogx(f,10*log10(SigPow(:,ch,d5,d6)),...
                    'color',colr,...
                    'DisplayName',['Signal ' labelstring]);
                
                
                colr = permute(linecolor(ch,2,d5,:),[1,4,2,3]);
                subplot(2,1,2) % plot of SNR
                semilogx(f,10*log10(SNR(:,ch,d5,d6)),...
                    'color',colr,...
                    'DisplayName',['SNR ' labelstring]);
                hold on
            end
        end
        subplot(2,1,1)
        title('Signal and Noise')
        xlabel('Frequency [Hz]')
        ylabel('Level [dB]')
        xlim([20,20000])
        
        subplot(2,1,2)
        title('Signal-to-Noise Ratio')
        xlabel('Frequency [Hz]')
        ylabel('Level [dB]')
        xlim([20,20000])
    end
end




% CONVOLVE AUDIO WITH INVERSE SWEEP (IN.audio2)
if isfield(IN,'audio2')
    IN = convolveaudiowithaudio2(IN,1,0,1);
else
    % We assume that convolution with audio2 has already been done.
    % Check that minimum length requirement is met
    if size(IN.audio,1) < floor(41*(2^IN.properties.MLSorder-1) ...
            + IN.fs*(2*IN.properties.gapdur + IN.properties.sweepdur) - 1)
        warndlg('Input audio is too short to analyse automatically. It looks like it has been truncated. Try inputting the recording (instead of the ''*'' convolved recording).','SilenceSweepAnalysis','modal');
        OUT = [];
        return
    end
end





% TIME ALIGN AUDIO WITH THE GAP BETWEEN MLS (USING CROSS-CORRELATION PEAK INDEX)
MLSgapmodel = [ones(MLSlen,1);...
    zeros(MLSlen,1);
    ones(2*MLSlen,1)];
MLSgapstart = sweeplen + gaplen + 20*MLSlen + 1;
x = ifftshift(ifft(conj(fft(...
    IN.audio(MLSgapstart-MLSlen-1:MLSgapstart+3*MLSlen-2,1,1,1,1,1).^2))...
    .* fft(MLSgapmodel)));
[~,mx]=max(x);
K = mx-round(length(x)/2)-1;
IN.audio = circshift(IN.audio,K);
clear x MLSgapmodel

% ANALYSE MLS AS NOISE, and GAP
MLSnoise1 = IN.audio(sweeplen+gaplen+11*MLSlen+1:sweeplen+gaplen+19*MLSlen,:,:,:,:,:);
MLSnoise2 = IN.audio(sweeplen+gaplen+22*MLSlen+1:sweeplen+gaplen+29*MLSlen,:,:,:,:,:);
gapmargin = round(MLSlen*0.05);
MLSgap = IN.audio(MLSgapstart+gapmargin:MLSgapstart+MLSlen-gapmargin,:,:,:,:,:);
NoisebeforeMLS = IN.audio(sweeplen+1+gapmargin:sweeplen+gaplen-gapmargin,:,:,:,:,:);
[SigPow2, NoiseDistPow,NoisebeforeMLSPow,SNR2,SINAD] = deal(zeros(floor(winlen/2),chans,dim5,dim6));
for ch = 1:chans
    for d5 = 1:dim5
        for d6 = 1:dim6
            [~,f,~,P1] = spectrogram(MLSnoise1(:,ch,1,1,d5,d6),wf,NOVERLAP,[],fs);
            [~,~,~,P2] = spectrogram(MLSnoise2(:,ch,1,1,d5,d6),wf,NOVERLAP,[],fs);
            [~,~,~,P3] = spectrogram(MLSgap(:,ch,1,1,d5,d6),wf,NOVERLAP,[],fs);
            [~,~,~,P4] = spectrogram(NoisebeforeMLS(:,ch,1,1,d5,d6),wf,NOVERLAP,[],fs);
            NoiseDistPow(:,ch,d5,d6) = mean(P3(1:floor(winlen/2),:),2);
            NoisebeforeMLSPow(:,ch,d5,d6) = mean(P4(1:floor(winlen/2),:),2);
            SigPow2(:,ch,d5,d6) = mean([P1(1:floor(winlen/2),:),...
                P2(1:floor(winlen/2),:)],2);
            SNR2(:,ch,d5,d6) = SigPow2(:,ch,d5,d6)./NoisebeforeMLSPow(:,ch,d5,d6); % although this looks inefficient, it is done here to avoid smoothing artefacts
            SINAD(:,ch,d5,d6) = SigPow2(:,ch,d5,d6)./NoiseDistPow(:,ch,d5,d6);
            if octsmooth > 0
                NoisebeforeMLSPow(:,ch,d5,d6) = octavesmoothing(NoisebeforeMLSPow(:,ch,d5,d6),octsmooth, fs);
                NoiseDistPow(:,ch,d5,d6) = octavesmoothing(NoiseDistPow(:,ch,d5,d6),octsmooth, fs);
                SigPow2(:,ch,d5,d6) = octavesmoothing(SigPow2(:,ch,d5,d6),octsmooth, fs);
                SNR2(:,ch,d5,d6) = octavesmoothing(SNR2(:,ch,d5,d6),octsmooth, fs);
                SINAD(:,ch,d5,d6) = octavesmoothing(SINAD(:,ch,d5,d6),octsmooth, fs);
            end
        end
    end
end
clear MLSgap NoisebeforeMLS P1 P2 P3 P4
f=f(1:floor(winlen/2));
if octsmooth > 0
    lowlimit = 128/(winlen/fs); % avoid very low freq hump error
    NoisebeforeMLSPow = NoisebeforeMLSPow(f>lowlimit,:,:,:,:,:);
    NoisebeforeMLSPow(NoisebeforeMLSPow<0)=0;
    NoiseDistPow = NoiseDistPow(f>lowlimit,:,:,:,:,:);
    NoiseDistPow(NoiseDistPow<0)=0;
    SigPow2 = SigPow2(f>lowlimit,:,:,:,:,:);
    SigPow2(SigPow2<0)=0;
    SNR2 = SNR2(f>lowlimit,:,:,:,:,:);
    SNR2(SNR2<0)=0;
    SINAD = SINAD(f>lowlimit,:,:,:,:,:);
    SINAD(SINAD<0)=0;
    f = f(f>lowlimit);
end


% Generate figure(s) for SNR analysis
for d6 = 1:dim6
    figure('Name','SNR & SINAD after inverse filtering');
    for ch = 1:chans
        for d5 = 1:dim5
            labelstring = [char(chanID(ch)), ' ', char(dim5ID(d5)), ' ' char(dim6ID(d6))];
            
            subplot(2,1,1) % plot of Signal and Noise spectra
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(NoisebeforeMLSPow(:,ch,d5,d6)),...
                'color',colr,...
                'DisplayName',['Noise ' labelstring]);
            hold on
            
            colr = permute(linecolor(ch,2,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(NoiseDistPow(:,ch,d5,d6)),...
                'color',colr,...
                'DisplayName',['N+D ' labelstring]);
            
            colr = permute(linecolor(ch,3,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(SigPow2(:,ch,d5,d6)),...
                'color',colr,...
                'DisplayName',['Sig ' labelstring]);
            
            
            colr = permute(linecolor(ch,2,d5,:),[1,4,2,3]);
            subplot(2,1,2) % plot of SNR
            semilogx(f,10*log10(SNR2(:,ch,d5,d6)),...
                'color',colr,...
                'DisplayName',['SNR ' labelstring]);
            hold on
            colr = permute(linecolor(ch,4,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(SINAD(:,ch,d5,d6)),...
                'color',colr,...
                'DisplayName',['SINAD ' labelstring]);
        end
    end
    subplot(2,1,1)
    title('Signal, Noise and Distortion+Noise')
    xlabel('Frequency [Hz]')
    ylabel('Level [dB]')
    xlim([20,20000])
    
    subplot(2,1,2)
    title('SNR and SINAD')
    xlabel('Frequency [Hz]')
    ylabel('Level [dB]')
    xlim([20,20000])
end


% ANALYSE IR FROM MLS
[ir1,ir2] = deal(zeros(2^IN.properties.MLSorder,chans,dim5,dim6));
impalign = 0;
for d5 = 1:dim5
    for d6 = 1:dim6
        ir1(:,:,d5,d6) = AnalyseMLSSequence(MLSnoise1(:,:,1,1,d5,d6),...
            0,8,IN.properties.MLSorder,DCCoupling,impalign);
        ir2(:,:,d6,d6) = AnalyseMLSSequence(MLSnoise2(:,:,1,1,d5,d6),...
            0,7,IN.properties.MLSorder,DCCoupling,impalign);
    end
end
MLSir = (8*ir1+7*ir2)./15;
clear ir1 ir2
%preshift = round(MLSlen*0.025);
MLSir = circshift(MLSir,round(winlen/2));
MLSir = MLSir(1:winlen,:,:,:,:,:);

wf = window(@blackmanharris,winlen);
wf(1:round(end/2)) = wf(1:round(end/2)).^4; % much stronger windowing in first half because we assume that is mainly noise

% ANALYSE IR FROM SWEEP, INCLUDING HARMONIC DISTORTION
IRstartindex = sweeplen+gaplen+32*MLSlen+gaplen+sweeplen-round(winlen/2)+1;
harmonicoffsets=round((log10(1:5))./...
    (1./sweeplen...
    .*log10(IN.properties.end_freq./IN.properties.start_freq))); % harmonics 1:5 are separated by more than MLSlen.
sweepIR1 = IN.audio(IRstartindex:IRstartindex+winlen-1,:,:,:,:,:);
sweepIR2 = IN.audio(IRstartindex-harmonicoffsets(2):IRstartindex-harmonicoffsets(2)+winlen-1,:,:,:,:,:);
sweepIR3 = IN.audio(IRstartindex-harmonicoffsets(3):IRstartindex-harmonicoffsets(3)+winlen-1,:,:,:,:,:);
sweepIR4 = IN.audio(IRstartindex-harmonicoffsets(4):IRstartindex-harmonicoffsets(4)+winlen-1,:,:,:,:,:);
sweepIR5 = IN.audio(IRstartindex-harmonicoffsets(5):IRstartindex-harmonicoffsets(5)+winlen-1,:,:,:,:,:);
if numel(sweepIR1)<1e6
    sweepspect1 = abs(fft(sweepIR1.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    sweepspect2 = abs(fft(sweepIR2.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    sweepspect3 = abs(fft(sweepIR3.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    sweepspect4 = abs(fft(sweepIR4.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    sweepspect5 = abs(fft(sweepIR5.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
else
    % nested for loops to reduce the chance of memory blow-out for
    % multidimensional measurements
    [sweepspect1,sweepspect2,sweepspect3,sweepspect4,sweepspect5] = ...
        deal(zeros(size(sweepIR1)));
    for ch = 1:chans
        for d5 = 1:dim5
            for d6 = 1:dim6
                sweepspect1 = abs(fft(sweepIR1(:,ch,1,1,d5,d6).*wf)).^2;
                sweepspect2 = abs(fft(sweepIR2(:,ch,1,1,d5,d6).*wf)).^2;
                sweepspect3 = abs(fft(sweepIR3(:,ch,1,1,d5,d6).*wf)).^2;
                sweepspect4 = abs(fft(sweepIR4(:,ch,1,1,d5,d6).*wf)).^2;
                sweepspect5 = abs(fft(sweepIR5(:,ch,1,1,d5,d6).*wf)).^2;
            end
        end
    end
end

% match MLS peak amplitude to sweepIR1 peak
MLSir = max(max(max(max(max(max(abs(sweepIR1))))))) .* MLSir ./ max(max(max(max(max(max(abs(MLSir)))))));
MLSspect = abs(fft(MLSir.*repmat(wf,[1,chans,dim5,dim6]))).^2;

% ANALYSE INVERSE-FILTERED SILENCE AT THE START TO ESTIMATE EFFECTIVE
% BACKGROUND NOISE USING EQUIVALENT TIME PERIODS TO THOSE OF THE SWEEP
IRstartindex = sweeplen-round(winlen/2)+1;
silenceIR1 = IN.audio(IRstartindex:IRstartindex+winlen-1,:,:,:,:,:);
silenceIR2 = IN.audio(IRstartindex-harmonicoffsets(2):IRstartindex-harmonicoffsets(2)+winlen-1,:,:,:,:,:);
silenceIR3 = IN.audio(IRstartindex-harmonicoffsets(3):IRstartindex-harmonicoffsets(3)+winlen-1,:,:,:,:,:);
silenceIR4 = IN.audio(IRstartindex-harmonicoffsets(4):IRstartindex-harmonicoffsets(4)+winlen-1,:,:,:,:,:);
silenceIR5 = IN.audio(IRstartindex-harmonicoffsets(5):IRstartindex-harmonicoffsets(5)+winlen-1,:,:,:,:,:);
if numel(silenceIR1)<1e6
    silencespect1 = abs(fft(silenceIR1.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    silencespect2 = abs(fft(silenceIR2.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    silencespect3 = abs(fft(silenceIR3.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    silencespect4 = abs(fft(silenceIR4.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
    silencespect5 = abs(fft(silenceIR5.*repmat(wf,[1,chans,1,1,dim5,dim6]))).^2;
else
    % nested for loops to reduce the chance of memory blow-out for
    % multidimensional measurements
    [silencespect1,silencespect2,silencespect3,silencespect4,silencespect5] = ...
        deal(zeros(size(silenceIR1)));
    for ch = 1:chans
        for d5 = 1:dim5
            for d6 = 1:dim6
                silencespect1 = abs(fft(silenceIR1(:,ch,1,1,d5,d6).*wf)).^2;
                silencespect2 = abs(fft(silenceIR2(:,ch,1,1,d5,d6).*wf)).^2;
                silencespect3 = abs(fft(silenceIR3(:,ch,1,1,d5,d6).*wf)).^2;
                silencespect4 = abs(fft(silenceIR4(:,ch,1,1,d5,d6).*wf)).^2;
                silencespect5 = abs(fft(silenceIR5(:,ch,1,1,d5,d6).*wf)).^2;
            end
        end
    end
end

t = (0:winlen-1)'./fs;
f = fs*(0:round(winlen/2))'./winlen;

if octsmooth > 0
    for ch = 1:chans
        for d5 = 1:dim5
            for d6 = 1:dim6
                MLSspect(:,ch,d5,d6) = octavesmoothing(MLSspect(:,ch,d5,d6),octsmooth, fs);
                sweepspect1(:,ch,1,1,d5,d6) = octavesmoothing(sweepspect1(:,ch,1,1,d5,d6),octsmooth, fs);
                sweepspect2(:,ch,1,1,d5,d6) = octavesmoothing(sweepspect2(:,ch,1,1,d5,d6),octsmooth, fs);
                sweepspect3(:,ch,1,1,d5,d6) = octavesmoothing(sweepspect3(:,ch,1,1,d5,d6),octsmooth, fs);
                sweepspect4(:,ch,1,1,d5,d6) = octavesmoothing(sweepspect4(:,ch,1,1,d5,d6),octsmooth, fs);
                sweepspect5(:,ch,1,1,d5,d6) = octavesmoothing(sweepspect5(:,ch,1,1,d5,d6),octsmooth, fs);
                silencespect1(:,ch,1,1,d5,d6) = octavesmoothing(silencespect1(:,ch,1,1,d5,d6),octsmooth, fs);
                silencespect2(:,ch,1,1,d5,d6) = octavesmoothing(silencespect2(:,ch,1,1,d5,d6),octsmooth, fs);
                silencespect3(:,ch,1,1,d5,d6) = octavesmoothing(silencespect3(:,ch,1,1,d5,d6),octsmooth, fs);
                silencespect4(:,ch,1,1,d5,d6) = octavesmoothing(silencespect4(:,ch,1,1,d5,d6),octsmooth, fs);
                silencespect5(:,ch,1,1,d5,d6) = octavesmoothing(silencespect5(:,ch,1,1,d5,d6),octsmooth, fs);
            end
        end
    end
    lowlimit = 128/(winlen/fs); % avoid very low freq hump error.
    % we zero (rather than delete) the LF components because this makes the
    % interpolation of the frequency scale for harmonic distortion simpler
    % to implement.
    MLSspect(f<lowlimit,:,:,:)=0;
    sweepspect1(f<lowlimit,:,:,:,:,:)=0;
    sweepspect2(f<lowlimit,:,:,:,:,:)=0;
    sweepspect3(f<lowlimit,:,:,:,:,:)=0;
    sweepspect4(f<lowlimit,:,:,:,:,:)=0;
    sweepspect5(f<lowlimit,:,:,:,:,:)=0;
    silencespect1(f<lowlimit,:,:,:,:,:)=0;
    silencespect2(f<lowlimit,:,:,:,:,:)=0;
    silencespect3(f<lowlimit,:,:,:,:,:)=0;
    silencespect4(f<lowlimit,:,:,:,:,:)=0;
    silencespect5(f<lowlimit,:,:,:,:,:)=0;
    
    MLSspect(MLSspect<0)=0;
    sweepspect1(sweepspect1<0)=0;
    sweepspect2(sweepspect2<0)=0;
    sweepspect3(sweepspect3<0)=0;
    sweepspect4(sweepspect4<0)=0;
    sweepspect5(sweepspect5<0)=0;
    silencespect1(silencespect1<0)=0;
    silencespect2(silencespect2<0)=0;
    silencespect3(silencespect3<0)=0;
    silencespect4(silencespect4<0)=0;
    silencespect5(silencespect5<0)=0;
end



for d6 = 1:dim6
    compplot=figure('Name','SilenceSweep IR & noise floor');
    for d5 = 1:dim5
        for ch = 1:chans
            labelstring = [char(chanID(ch)), ' ', char(dim5ID(d5)), ' ' char(dim6ID(d6))];
            subplot(3,2,1)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            plot(t,10*log10(MLSir(:,ch,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
                     
            subplot(3,2,2)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            plot(t,10*log10(sweepIR1(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(t,10*log10(silenceIR1(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,3)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            plot(t,10*log10(sweepIR2(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(t,10*log10(silenceIR2(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,4)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            plot(t,10*log10(sweepIR3(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(t,10*log10(silenceIR3(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,5)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            plot(t,10*log10(sweepIR4(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(t,10*log10(silenceIR4(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,6)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            plot(t,10*log10(sweepIR5(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(t,10*log10(silenceIR5(:,ch,1,1,d5,d6).^2),...
                'color',colr,...
                'DisplayName',labelstring);
            
            
        end
    end
    subplot(3,2,1)
    title('MLS')
    ylabel('Level [dB]')
    subplot(3,2,2)
    title('Sweep linear response')
    subplot(3,2,3)
    title('Sweep 2nd harmonic')
    ylabel('Level [dB]')
    subplot(3,2,4)
    title('Sweep 3rd harmonic')
    subplot(3,2,5)
    title('Sweep 4th harmonic')
    xlabel('Time [s]')
    ylabel('Level [dB]')
    subplot(3,2,6)
    title('Sweep 5th harmonic')
    xlabel('Time [s]')
    
    iplots = get(compplot,'Children');
    if length(iplots) > 1
        xlims = cell2mat(get(iplots,'Xlim'));
        set(iplots,'Xlim',[min(xlims(:,1)) max(xlims(:,2))])
        ylims = cell2mat(get(iplots,'Ylim'));
        set(iplots,'Ylim',[min(ylims(:,1)) max(ylims(:,2))])
        uicontrol('Style', 'pushbutton', 'String', 'Axes limits',...
            'Position', [0 0 65 30],...
            'Callback', 'setaxeslimits');
    end
end

for d6 = 1:dim6
    compplot=figure('Name','SilenceSweep IR spectrum & noise floor');
    for d5 = 1:dim5
        for ch = 1:chans
            labelstring = [char(chanID(ch)), ' ', char(dim5ID(d5)), ' ' char(dim6ID(d6))];
            subplot(3,2,1)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(MLSspect(1:length(f),ch,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            
            subplot(3,2,2)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(sweepspect1(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(f,10*log10(silencespect1(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,3)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(sweepspect2(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(f,10*log10(silencespect2(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,4)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(sweepspect3(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(f,10*log10(silencespect3(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,5)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(sweepspect4(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(f,10*log10(silencespect4(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            
            subplot(3,2,6)
            colr = permute(linecolor(ch,5,d5,:),[1,4,2,3]);
            semilogx(f,10*log10(sweepspect5(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
            hold on
            colr = permute(linecolor(ch,1,d5,:),[1,4,2,3]);
            plot(f,10*log10(silencespect5(1:length(f),ch,1,1,d5,d6)),...
                'color',colr,...
                'DisplayName',labelstring);
        end
    end
    subplot(3,2,1)
    title('MLS')
    ylabel('Level [dB]')
    subplot(3,2,2)
    title('Sweep linear response')
    subplot(3,2,3)
    title('Sweep 2nd harmonic')
    ylabel('Level [dB]')
    subplot(3,2,4)
    title('Sweep 3rd harmonic')
    subplot(3,2,5)
    title('Sweep 4th harmonic')
    xlabel('Frequency [Hz]')
    ylabel('Level [dB]')
    subplot(3,2,6)
    title('Sweep 5th harmonic')
    xlabel('Frequency [Hz]')
    iplots = get(compplot,'Children');
    if length(iplots) > 1
        %xlims = cell2mat(get(iplots,'Xlim'));
        %set(iplots,'Xlim',[min(xlims(:,1)) max(xlims(:,2))])
        set(iplots,'Xlim',[20 20000])
        ylims = cell2mat(get(iplots,'Ylim'));
        set(iplots,'Ylim',[min(ylims(:,1)) max(ylims(:,2))])
        uicontrol('Style', 'pushbutton', 'String', 'Axes limits',...
            'Position', [0 0 65 30],...
            'Callback', 'setaxeslimits');
    end
end

for d6 = 1:dim6
    compplot = figure('Name','Harmonic distortion relative to linear response');
    numberofsubplots = chans * dim5;
    maxsubplots = 100;
    if numberofsubplots > maxsubplots, numberofsubplots = maxsubplots; end
    [r, c] = subplotpositions(numberofsubplots,0.7);
    plotnum = 1;
    for d5 = 1:dim5
        for ch = 1:chans
            if plotnum <= maxsubplots
                subplot(r,c,plotnum)
                h = sweepspect2(1:length(f),ch,1,1,d5,d6);
                h(h<=silencespect2(1:length(f),ch,1,1,d5,d6)*db2pow(thresholddB)) = 0;
                h0 = interp(sweepspect1((1:length(f)),ch,1,1,d5,d6),2);
                h = 10*log10(h ./ h0(1:length(f)));
                hindex = isreal(h) | ~isnan(h);
                h(isinf(h))=nan;
                semilogx(f(hindex)./2,real(h(hindex)),...
                    'color',[1,0,0],...
                    'DisplayName','2nd harmonic');
                title([char(chanID(ch)) ' ' char(dim5ID(d5))])
                hold on
                
                h = sweepspect3(1:length(f),ch,1,1,d5,d6);
                h(h<=silencespect3(1:length(f),ch,1,1,d5,d6)*db2pow(thresholddB)) = 0;
                h0 = interp(sweepspect1((1:length(f)),ch,1,1,d5,d6),3);
                h = 10*log10(h ./ h0(1:length(f)));
                hindex = isreal(h) | ~isnan(h);
                h(isinf(h))=nan;
                semilogx(f(hindex)./3,real(h(hindex)),...
                    'color',[0.8,0.8,0],...
                    'DisplayName','3rd harmonic');
                
                h = sweepspect4(1:length(f),ch,1,1,d5,d6);
                h(h<=silencespect4(1:length(f),ch,1,1,d5,d6)*db2pow(thresholddB)) = 0;
                h0 = interp(sweepspect1((1:length(f)),ch,1,1,d5,d6),4);
                h = 10*log10(h ./ h0(1:length(f)));
                hindex = isreal(h) | ~isnan(h);
                h(isinf(h))=nan;
                semilogx(f(hindex)./4,real(h(hindex)),...
                    'color',[0,0.8,0],...
                    'DisplayName','4th harmonic');
                
                h = sweepspect5(1:length(f),ch,1,1,d5,d6);
                h(h<=silencespect5(1:length(f),ch,1,1,d5,d6)*db2pow(thresholddB)) = 0;
                h0 = interp(sweepspect1((1:length(f)),ch,1,1,d5,d6),5);
                h = 10*log10(h ./ h0(1:length(f)));
                hindex = isreal(h) | ~isnan(h);
                h(isinf(h))=nan;
                semilogx(f(hindex)./5,real(h(hindex)),...
                    'color',[0,0,1],...
                    'DisplayName','5th harmonic');
                
                semilogx([20 20000], [0 0],...
                    'color',[0.6 0.6 0.6]);
                xlim([20 10000])
                ylim([-120 20])
                xlabel('Excitation Freq [Hz]')
                ylabel('Relative Level [dB]')
            end
            plotnum = plotnum+1;
        end
    end
    iplots = get(compplot,'Children');
    if length(iplots) > 1
        %xlims = cell2mat(get(iplots,'Xlim'));
        %set(iplots,'Xlim',[min(xlims(:,1)) max(xlims(:,2))])
        set(iplots,'Xlim',[20 20000])
        ylims = cell2mat(get(iplots,'Ylim'));
        set(iplots,'Ylim',[min(ylims(:,1)) max(ylims(:,2))])
        uicontrol('Style', 'pushbutton', 'String', 'Axes limits',...
            'Position', [0 0 65 30],...
            'Callback', 'setaxeslimits');
    end
end



OUT.funcallback.name = 'SilenceSweepAnalysis.m';
OUT.funcallback.inarg = {octsmooth,thresholddB};


%**************************************************************************
% Copyright (c) 2015, Densil Cabrera
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
%
%  * Redistributions of source code must retain the above copyright notice,
%    this list of conditions and the following disclaimer.
%  * Redistributions in binary form must reproduce the above copyright
%    notice, this list of conditions and the following disclaimer in the
%    documentation and/or other materials provided with the distribution.
%  * Neither the name of the The University of Sydney nor the names of its contributors
%    may be used to endorse or promote products derived from this software
%    without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
% TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
% PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
% OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
% EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
% PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
% PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
% LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
% NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%**************************************************************************