% =========================================================================
% calculate_tSNR_mTBI_predict.m
%
% Purpose:
% This script computes voxelwise and regional tSNR (temporal Signal-to-Noise
% Ratio) maps from preprocessed 4D fMRI data across 3 functional runs for a
% given subject and session. It was developed for a harmonisation study
% involving a *single travelling head* scanned at *three imaging centres*
% across *six sessions*, each session containing three runs.
%
% Input Requirements:
% - Preprocessed 4D fMRI BOLD data in BIDS format (one run per file)
% - Grey matter mask and five ROI masks in EPI space
%   (stored in `derivatives/<sub>/<ses>/ROI_masks/`)
%
% Output:
% - One tSNR map per run:       `tsnr_map_run-XX.nii.gz`
% - One summary CSV per run:    `tsnr_summary_run-XX.csv`
% - One average summary CSV:    `tsnr_summary_session_avg.csv`
%   (mean across all 3 runs)
%
% 🔧 Key Notes:
% - The script uses the NIfTI toolbox by Jimmy Shen (Tools for NIfTI and ANALYZE image)
%   👉 You must add it to your MATLAB path using `addpath()`
%
%   To ensure the calculated tSNR values accurately reflect true signal 
%   variability and to exclude artefactual or background voxels, a threshold 
%   was applied: only voxels with mean signal intensity greater than 5% 
%
% =========================================================================

%% === Add NIfTI toolbox path ===
% Replace this with your actual path
addpath(genpath('/path_to/nifti_toolbox'));

%% === Define subject and session ===
sub_id = 'sub-0001';
ses_id = 'ses-01N';

%% === Settings ===
run_list = {'run-01', 'run-02', 'run-03'};
roi_labels = {'frontal', 'cingulate', 'motor', 'occipital', 'parietal'};
roi_names  = {'Frontal', 'Cingulate', 'Motor', 'Occipital', 'Parietal'};

%% === Load GM and ROI masks ===
ROI_mask_dir = fullfile('derivatives', sub_id, ses_id, 'ROI_masks');
gm_mask_file = fullfile(ROI_mask_dir, 'gm_mask_epi.nii.gz');
gm_mask = load_untouch_nii(gm_mask_file);
gm_mask = gm_mask.img > 0;

roi_masks = cell(size(roi_labels));
for r = 1:length(roi_labels)
    roi_file = fullfile(ROI_mask_dir, [roi_labels{r} '_roi_epi.nii.gz']);
    roi = load_untouch_nii(roi_file);
    roi_masks{r} = roi.img > 0;
end

%% === Output directory ===
out_dir = fullfile('derivatives', 'tsnr', sub_id, ses_id);
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

session_results = cell(length(roi_labels)+2, 4);
session_results(1,:) = {'Region', 'Run-01', 'Run-02', 'Run-03'};

%% === Loop over 3 runs ===
for rr = 1:length(run_list)
    run_id = run_list{rr};
    fprintf('[%s %s %s] Processing...\n', sub_id, ses_id, run_id);

    % Input BOLD path
    bold_file = fullfile('bids', sub_id, ses_id, 'func', ...
        sprintf('%s_%s_task-CRT_%s_bold.nii.gz', sub_id, ses_id, run_id));
    
    % Output file names
    tsnr_map_out = fullfile(out_dir, sprintf('tsnr_map_%s.nii.gz', run_id));
    tsnr_csv_out = fullfile(out_dir, sprintf('tsnr_summary_%s.csv', run_id));

    % Load fMRI data
    nii = load_untouch_nii(bold_file);
    data = double(nii.img);  % X × Y × Z × T

    % Calculate mean and std over time
    mean_signal = mean(data, 4);
    std_signal  = std(data, 0, 4);

    % Apply 5% threshold to exclude low-signal voxels
    threshold = 0.05 * max(mean_signal(:));
    valid_voxels = mean_signal > threshold;

    % Compute voxelwise tSNR
    tsnr_map = zeros(size(mean_signal));
    tsnr_map(valid_voxels) = mean_signal(valid_voxels) ./ std_signal(valid_voxels);

    % Save tSNR map
    tsnr_nii = nii;
    tsnr_nii.img = tsnr_map;
    tsnr_nii.hdr.dime.dim(5) = 1;  % Force 3D
    save_untouch_nii(tsnr_nii, tsnr_map_out);

    % Compute ROI mean tSNR
    results = {'Region', 'Mean_tSNR'};
    gm_tsnr = tsnr_map(gm_mask & valid_voxels);
    results(end+1,:) = {'Grey Matter', mean(gm_tsnr(:), 'omitnan')};
    session_results{2, rr+1} = mean(gm_tsnr(:), 'omitnan');

    for r = 1:length(roi_names)
        roi_gm = roi_masks{r} & gm_mask & valid_voxels;
        roi_tsnr = tsnr_map(roi_gm);
        region_name = [roi_names{r} ' GM'];
        results(end+1,:) = {region_name, mean(roi_tsnr(:), 'omitnan')};
        session_results{r+2,1} = region_name;
        session_results{r+2, rr+1} = mean(roi_tsnr(:), 'omitnan');
    end

    % Save run summary
    writecell(results, tsnr_csv_out);
end

%% === Save session average summary ===
for row = 2:size(session_results,1)
    values = cell2mat(session_results(row, 2:4));
    session_results{row, 5} = mean(values, 'omitnan');
end
session_results(1,5) = {'SessionMean'};

session_avg_csv = fullfile(out_dir, 'tsnr_summary_session_avg.csv');
writecell(session_results, session_avg_csv);
fprintf('[%s %s] ✅ All runs complete. Summary saved.\n', sub_id, ses_id);
