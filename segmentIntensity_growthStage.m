%% segment phase and fluorescent image and build data matrix

% goal: extract cell size and HiPR-FISH signal from phase and GFP images

% strategy:
%
% Part ONE: measurements from raw images
%
%   0. initialize experiment data
%   0. define image name of each channel
%   0. for each sample, build directory and loop through stacks
%   1. for each stack per sample, make a mask to isolate pixels representing cells
%   2. quantify fluorescence intensity inside mask 
%   3. quantify fluorescence intenstiy outside mask
%
% Part TWO:
%
%   4. trim measured particules by size
%   5. save new data matrix
%
% Part THREE:
%
%   6. plot channel by channel comparison


% ok, let's go!

% last updated: jen, 2021 April 20
% commit: analyze 2021-04-20 experiment


%% Part ONE: measurements from raw images 

clc
clear
cd('/Users/jen/Documents/TropiniLab/Data/such-hipr/sourcedata')
load('metadata.mat')

% 0. initialize experiment data
index = 3; % 2021-04-20
date = metadata{index}.date;
magnification = metadata{index}.magnification;
samples = metadata{index}.samples;

data_folder = strcat('/Users/jen/Documents/TropiniLab/Molecular_tools/HiPR_fish/',date);
cd(data_folder)
px_size = 11/magnification; % Ti2 has 11x11 um pixels pre-magnification



% 0. define image name of each channel
prefix = 'img_';
suffix = '_position000_time000000000_z000.tif';
name_phase = strcat(prefix,'channel000',suffix);
name_gfp = strcat(prefix,'channel001',suffix);
clear prefix suffix



% 0. for each sample, build directory and loop through stacks
for ss = 1:length(samples)
    
    cd(data_folder)
    sDirectory = dir(strcat(samples{ss},'_*'));
    names = {sDirectory.name};
    
    
    %   1. for each stack per sample, make a mask to isolate pixels representing cells
    for stk = 1:length(names)
        
        cd(data_folder)
        current_stack = names{stk};
        cd(strcat(current_stack,'/Default'))
        
        %   1a. read phase, gfp, mcherry and dapi images
        img_phase = imread(name_phase);
        img_gfp = imread(name_gfp);
        
        
        %   1b. make mask from phase image
        figure(1)
        imshow(img_phase, 'DisplayRange',[2000 5000]); %lowering right # increases num sat'd pxls
        
        %   i. gaussian smoothing of phase image
        phase_smoothed = imgaussfilt(img_phase,0.8);
        %figure(2)
        %imshow(phase_smoothed, 'DisplayRange',[500 2500]);
        
        %   ii. edge detection of cells in phase image
        bw = edge(phase_smoothed,'sobel');
        %figure(3)
        %imshow(bw);%, 'DisplayRange',[2000 6000]);
        
        %   iii. clean up edge detection
        se = strel('disk',1); % structuring element; disk-shaped with radius of 3 pixels
        bw_dil = imdilate(bw, se); % dilate
        %figure(4)
        %imshow(bw_dil);
        
        bw_fill = imfill(bw_dil, 'holes'); % fill
        %figure(5)
        %imshow(bw_fill);
        
        bw_final = imerode(imerode(bw_fill,se),se); % erode 2x to smooth; this is your final mask
        figure(6)
        imshow(bw_final)
        
        %   iv. segment cells
        cc = bwconncomp(bw_final);
        
        %   v. gather properties for each identified particle
        stats = regionprops(cc,'Area','Centroid','MajorAxisLength','MinorAxisLength','Eccentricity','Orientation');
        clear bw bw_dil bw_fill se phase_smoothed
        
        
        
        %   2. quantify fluorescence intensity inside mask (all channels)
        
        %   2a. overlay mask with fluorescence image by dot-product
        masked_gfp = bw_final .* double(img_gfp); % convert uint16 image to double class

        
        %   2b. compute the mean fluorescence intensity for each particle in mask
        for pp = 1:cc.NumObjects
            
            pixel_id_of_cell = []; % initialize
            pixel_id_of_cell = cc.PixelIdxList{pp}; % pixel index where the cell of interest is
            
            cell_intensity_gfp(pp) = mean(masked_gfp(pixel_id_of_cell)); % compute the mean intensity of pixels in the cell
            
        end
        clear pp pixel_id_of_cell
        

        
        %   3. quantify fluorescence intenstiy outside mask (all channels)
        
        %   3a. background mask is inverse of cell mask
        bg_mask = imcomplement(bw_final);
        %figure(10)
        %imshow(bg_mask)
        
        %   3b. overlay background mask with fluorescence image by dot-product
        bg_gfp = bg_mask .* double(img_gfp); % convert uint16 image to double class

        
        %   3c. compute the mean background intensity for each channel
        bg_gfp_mean = mean(mean(bg_gfp));
        clear bg_mask
        
        
       
        % 4. store mean fluorescent intensity of each cell and background in data structure
        for particle = 1:cc.NumObjects
            
            % cell intensity
            stats(particle).gfp_cell = cell_intensity_gfp(particle);
            
            % mean background intensity
            stats(particle).gfp_bg = bg_gfp_mean;
           
        end
        clear cell_intensity_gfp img_phase img_gfp  bg_gfp 
        clear masked_gfp  bw_final particle cc
        
        
        % 5. store particle measurements into cell per stack
        dm{stk,ss} = stats;
        clear bg_gfp_mean
        
    end
    clear stats
    
end
clear name_gfp name_phase names 
clear ss stk current_stack

cd('/Users/jen/Documents/TropiniLab/Data/such-hipr/sourcedata')
save(strcat('dm-segmentIntensity-',date,'.mat'),'dm')

%% Part TWO: trim measured data and create data structure


clear
clc
cd('/Users/jen/Documents/TropiniLab/Data/such-hipr/sourcedata')
load('metadata.mat')

% 0. initialize experiment data
index = 3; % 2021-04-20
date = metadata{index}.date;
load(strcat('dm-segmentIntensity-',date,'.mat'))

samples = metadata{index}.samples;
magnification = metadata{index}.magnification;
px_size = 11/magnification; 


% 1. concatenate data from same sample
for col = 1:length(samples)
    
    current_sample = dm(:,col);
    num_stacks = sum(~cellfun(@isempty,current_sample));
    
    combined_sample_data = [];
    for sstack = 1:num_stacks
        stk_data = current_sample{sstack,1};
        combined_sample_data = [combined_sample_data; stk_data];
    end
    clear sstack
    combined_particles{1,col} = combined_sample_data;
    
end
clear col combined_sample_data num_stacks current_sample stk_data



% 2. convert measurements to microns based on imaging specifications     
for sample = 1:length(samples)
    
    sample_particles = combined_particles{1,sample};
    
    % 2a. convert x,y coordinate data
    x_position = [];
    y_position = [];
    for ii = 1:length(sample_particles)
        
        centroid = sample_particles(ii).Centroid.*px_size;
        x_position = [x_position; centroid(1)];
        y_position = [y_position; centroid(2)];
        
    end
    parameter_unit.X = x_position;
    parameter_unit.Y = y_position;
    clear particle x_position y_position centroid ii
    
    
    % 2b. convert area
    area = extractfield(sample_particles,'Area')';
    parameter_unit.A = area.*px_size^2;
    clear area
    
    
    % 2c. major & minor axis
    majorAxis = extractfield(sample_particles,'MajorAxisLength')';
    minorAxis = extractfield(sample_particles,'MinorAxisLength')';
    parameter_unit.MajAx = majorAxis.*px_size;
    parameter_unit.MinAx = minorAxis.*px_size;
    clear majorAxis minorAxis
    
    
    % 2d. cell intensity
    GFP_cell = extractfield(sample_particles,'gfp_cell')';
    parameter_unit.gfp_cell = GFP_cell;
    clear GFP_cell
    
    
    % 2e. background intensity of corresponding image
    GFP_bg = extractfield(sample_particles,'gfp_bg')';
    parameter_unit.gfp_bg = GFP_bg;
    clear GFP_bg
    
    
    % 2f. eccentricity and angle
    ecc = extractfield(sample_particles,'Eccentricity')';
    angle = extractfield(sample_particles,'Orientation')';
    parameter_unit.Ecc = ecc;
    parameter_unit.Angle = angle;
    clear ecc angle
    
    
    % 3. trim particles by width
    %    values are set as recorded in whos_a_cell.m
    
    % 3b. trim by width
    TrimField = 'MinAx';  % choose relevant characteristic to restrict, run several times to apply for several fields
    if sample < 4
        LowerBound = 1;         % lower bound for exponential 381 (see whos_a_cell.m)
    elseif sample < 7
        LowerBound = 1.3;       % lower bound for exponential BW25113 (see whos_a_cell.m)
    elseif sample < 9
        LowerBound = 1;         % lower bound for stationary 381 (see whos_a_cell.m)
    else
        LowerBound = 1;         % lower bound for stationary BW25113 (see whos_a_cell.m)
    end
    UpperBound = 176;     % whole image length
    p_trim = ParticleTrim_glycogen(parameter_unit,TrimField,LowerBound,UpperBound);
    

    % 4. store final data 
    converted_data{1,sample} = p_trim;
    
end
clear sample sample_particles p_trim UpperBound LowerBound
    
%% Part THREE: visualize measured data

% 1. isolate single cells from clumps
% 2. plot absolute intensities of background, single cells, clumps
% 3. plot single cell and clump intensities normalized by background

clc

counter = 0;% counter_stat = 0;
cv_single = zeros(length(samples),1);
cv_clumps = zeros(length(samples),1);

% for each sample
for smpl = 1:length(samples)
    
    % 0. gather cell width and intensity data
    sample_data = converted_data{1,smpl};
    cell_width = sample_data.MinAx;
    cell_gfp = sample_data.gfp_cell; % mean cell fluorescence
    bg_gfp = sample_data.gfp_bg; % mean bg fluorescence
    
    
    % 1. isolate single cells from clumps
    if smpl < 4
        clumpThresh = 1.8;  % min width of clumps for exponential 381
    elseif smpl < 7
        clumpThresh = 2.4;  % min width of clumps for exponential BW25113 (see whos_a_cell.m)
    elseif smpl < 9
        clumpThresh = 1.6;  % min width of clumps for stationary 381
    else
        clumpThresh = 1.9;  % min width of clumps for stationary BW25113
    end
    
    single_gfp = cell_gfp(cell_width <= clumpThresh);
    single_bg = bg_gfp(cell_width <= clumpThresh);
    clump_gfp = cell_gfp(cell_width > clumpThresh);
    clump_bg = bg_gfp(cell_width > clumpThresh);
    
    
    % 2. box plots of absolute intensities of background, single cells, clumps
    
    n_single = length(single_bg);
    n_clump = length(clump_bg);
    
    counter = counter + 1;
    
    figure(7)
    subplot(1,length(samples),counter)
    x = [single_bg; single_gfp; clump_bg; clump_gfp];
    g = [zeros(length(single_bg), 1); ones(length(single_gfp), 1); 2*ones(length(clump_bg), 1); 3*ones(length(clump_gfp), 1)];
    boxplot(x,g)
    set(gca,'xticklabel',{'BG','1x','BG', 'Clump'})
    title(strcat(samples{smpl},', n =',num2str(n_single),' and n =',num2str(n_clump)))
    ylim([0 10000])
    
    
    % 3. plot single cell and clump intensities normalized by background
    
    % cell fluorescence normalized by bg fluorescence
    norm_single = single_gfp./single_bg;
    norm_clump = clump_gfp./clump_bg;
    norm_n = [length(norm_single); length(norm_clump)]; 
    
    figure(17)
    subplot(1,length(samples),counter)
    xx = [norm_single; norm_clump];
    gg = [zeros(length(norm_single), 1); ones(length(norm_clump), 1)];
    boxplot(xx,gg)
    set(gca,'xticklabel',{'1x','Clump'})
    title(strcat(samples{smpl},', n =',num2str(norm_n(1)),' and n =',num2str(norm_n(2))))
    ylim([0 12.5])
    
    
    % 4. calculate coefficient of variation (standard deviation divided by mean)
    cv_single(smpl) = std(norm_single)/mean(norm_single);
    cv_clumps(smpl) = std(norm_clump)/mean(norm_clump);
    
    
end

%% Part FOUR. save boxplots

cd('/Users/jen/Documents/TropiniLab/Data/HiPR_fish')

figure(17)
saveas(gcf,strcat(date,'-summary'),'epsc')
close(gcf)

