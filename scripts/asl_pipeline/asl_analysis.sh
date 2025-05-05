#!/bin/bash

# ============================================================================
# Script: asl_analysis.sh
#
# 📌 Purpose:
# Preprocesses ASL MRI data for a single subject-session using vendor-specific
# pipelines (Philips or Siemens), determined from the session ID. Based on BIDS.
#
# 🧠 Scanner Type Handling:
#   - Sessions ending in 'N' → Philips pipeline
#   - Sessions ending in 'B' → Siemens pipeline
#
# 🔔 Study Design:
#   - One travelling head subject in the mTBI predict study
#   - Scanned across 2 different scanners (Philips and Siemens)
#   - 2 sessions per scanner (total of 4 sessions)
#   - One travelling head subject
#   - Scanned across 2 different scanners (Philips and Siemens)
#   - 2 sessions per scanner (total of 4 sessions)
#
# 📁 Input Structure:
#   - Raw ASL data:       bids/<sub>/<ses>/perf/
#   - Fieldmaps:          bids/<sub>/<ses>/fmap/
#   - Anatomical T1:      derivatives/fsl_anat/<sub>/<ses>/
#
# 📄 Output:
#   - Preprocessed outputs: derivatives/asl_analysis/<sub>/<ses>/
#
# ⚙️ Dependencies:
#   - FSL ≥ 6.0.6
# ============================================================================
# 🔁 Steps Performed:
# 1. Identify scanner type from session ID (Philips = N, Siemens = B)
# 2. Create gm masks and acqparams.txt for TOPUP
# 3. Merge SE fieldmaps (AP/PA or PA/AP) for distortion correction
# 4. Run `topup` to estimate distortions
# 5. Apply `applytopup` to calibration/control and ASL timeseries
# 6. Generate mean M0 image
# 7. Compute perfusion difference image using `asl_file`
# 8. Run `oxford_asl` with anatomical info, GM segmentation, and PVC
# ============================================================================

STARTTIME=$(date +%s)
echo "Running on $(hostname)"
echo "Started at: $(date +%F_%T)"

# === USER INPUT ===
sub_id="sub-0001"
ses_id="ses-02N"  # Set to 'ses-XXN' for Philips, 'ses-XXB' for Siemens

# === Derived Paths ===
scanner_type=${ses_id: -1}
root_dir=$(pwd)
bids_sub_dir="${root_dir}/bids/${sub_id}/${ses_id}"
perf_dir="${bids_sub_dir}/perf"
fmap_dir="${bids_sub_dir}/fmap"
anat_dir="${root_dir}/derivatives/fsl_anat/${sub_id}/${ses_id}"
out_dir="${root_dir}/derivatives/asl_analysis/${sub_id}/${ses_id}"
mkdir -p "${out_dir}"
cd "${out_dir}" || exit 1

# Copy and binarize GM PVE map to ASL derivatives 
pve_gm_src="${anat_dir}/T1_fast_pve_1.nii.gz"
pve_gm_dest="${out_dir}/T1_fast_pve_1.nii.gz"
gm_mask="${out_dir}/gm_mask_std.nii.gz"

if [ -f "$pve_gm_src" ]; then
  echo "Copying GM partial volume estimate and generating binary GM mask..."
  cp "$pve_gm_src" "$pve_gm_dest"
  fslmaths "$pve_gm_dest" -thr 0.5 -bin "$gm_mask"
  echo " GM mask saved as: $gm_mask"
else
  echo "ERROR: GM PVE file not found at $pve_gm_src"
  exit 1
find GM PVE map at $pve_gm_src"
  exit 1
fi
root_dir=$(pwd)
bids_sub_dir="${root_dir}/bids/${sub_id}/${ses_id}"
perf_dir="${bids_sub_dir}/perf"
fmap_dir="${bids_sub_dir}/fmap"
anat_dir="${root_dir}/derivatives/fsl_anat/${sub_id}/${ses_id}"
out_dir="${root_dir}/derivatives/asl_analysis/${sub_id}/${ses_id}"
mkdir -p "${out_dir}"
cd "${out_dir}" || exit 1


# === Set acqparams.txt ===
if [ "$scanner_type" == "N" ]; then
  echo "Philips PCASL pipeline selected"
  echo -e "0 1 0 0.0379386\n0 -1 0 0.0379386" > acqparams.txt
else
  echo "Siemens PCASL pipeline selected"
  echo -e "0 -1 0 0.0541496\n0 1 0 0.0541496" > acqparams.txt
fi

# === Philips: Multi-PLD PCASL with reverse AP ===
if [ "$scanner_type" == "N" ]; then
  echo "Preparing Philips PLD volumes and reverse AP..."

  fslmaths "${perf_dir}/${sub_id}_${ses_id}_acq-1200msPLD_asl.nii.gz" -Tmean pcASL_PA
  fslmaths "${perf_dir}/${sub_id}_${ses_id}_reverse_pcasl_1200.nii.gz" -Tmean pcASL_AP

  fslmerge -t pcASL_PA_main \
    "${perf_dir}/${sub_id}_${ses_id}_acq-200msPLD_asl.nii.gz" \
    "${perf_dir}/${sub_id}_${ses_id}_acq-700msPLD_asl.nii.gz" \
    "${perf_dir}/${sub_id}_${ses_id}_acq-1200msPLD_asl.nii.gz" \
    "${perf_dir}/${sub_id}_${ses_id}_acq-1700msPLD_asl.nii.gz" \
    "${perf_dir}/${sub_id}_${ses_id}_acq-2200msPLD_asl.nii.gz"

  fslmerge -t ASL_PA_AP pcASL_PA pcASL_AP

  cp "${perf_dir}/${sub_id}_${ses_id}_m0scan.nii.gz" M0.nii.gz
  fslmaths M0.nii.gz -Tmean M0_avg

  topup --imain=ASL_PA_AP.nii.gz --datain=acqparams.txt --config=b02b0.cnf \
        --out=topup_b0_reverseb0 --iout=topup_b0_reverseb0_iout --fout=topup_b0_reverseb0_fout

  applytopup --imain=pcASL_PA,pcASL_AP --topup=topup_b0_reverseb0 --datain=acqparams.txt \
             --inindex=1,2 --method=jac --out=aslcalib_corr

  applytopup --imain=pcASL_PA_main.nii.gz --topup=topup_b0_reverseb0 --datain=acqparams.txt \
             --inindex=1 --method=jac --out=aslct_corr

  asl_file --data=aslct_corr.nii.gz --ntis=5 --iaf=ct --ibf=tis --rpts=12,12,12,20,30 \
           --diff --out=diff_asl --mean=asl_mean_diff

  oxford_asl -i diff_asl -o output --iaf=diff \
    --tis=1.6,1.6,1.6,1.6,1.6,1.6,2.1,2.1,2.1,2.1,2.1,2.1,2.6,2.6,2.6,2.6,2.6,2.6,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6 \
    --casl --bolus=1.4 --slicedt=0.018 --t1=1.3 --t1b=1.65 --alpha=0.85 \
    --spatial -c M0_avg.nii.gz --tr=10 --cgain=1.0 --cmethod=voxel --te=14 --t2bl=0.15 \
    --fslanat="${anat_dir}" --pvcorr

# === Siemens: Single ASL volume ===
elif [ "$scanner_type" == "B" ]; then
  cp "${perf_dir}/${sub_id}_${ses_id}_asl.nii.gz" ASL_AP.nii.gz
  cp "${fmap_dir}/${sub_id}_${ses_id}_acq-asl_dir-AP_epi.nii.gz" SE_AP.nii.gz
  cp "${fmap_dir}/${sub_id}_${ses_id}_acq-asl_dir-PA_epi.nii.gz" SE_PA.nii.gz

  # Siemens PCASL includes:
  # - First 86 volumes: ASL control/label
  # - Last 2 volumes: M0 calibration
  fslroi ASL_AP.nii.gz pcASL 0 86
  fslroi ASL_AP.nii.gz M0 88 2
  fslmaths M0.nii.gz -Tmean M0_avg

  fslmerge -t ASL_AP_PA SE_AP.nii.gz SE_PA.nii.gz

  topup --imain=ASL_AP_PA --datain=acqparams.txt --config=b02b0.cnf \
        --out=topup_b0 --iout=topup_iout --fout=topup_fout

  applytopup --imain=SE_AP,SE_PA --topup=topup_b0 --datain=acqparams.txt \
             --inindex=1,2 --method=jac --out=aslcalib_corr

  applytopup --imain=ASL_AP.nii.gz --topup=topup_b0 --datain=acqparams.txt \
             --inindex=1 --method=jac --out=asltc_corr

  asl_file --data=pcASL.nii.gz --ntis=5 --ibf=tis --rpts=12,12,12,20,30 \
           --diff --out=diff_asl --mean=asl_mean_diff

  oxford_asl -i diff_asl -o output --iaf=diff \
    --tis=1.6,1.6,1.6,1.6,1.6,1.6,2.1,2.1,2.1,2.1,2.1,2.1,2.6,2.6,2.6,2.6,2.6,2.6,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.1,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6,3.6 \
    --casl --bolus=1.4 --slicedt=0.018 --t1=1.3 --t1b=1.65 --alpha=0.85 \
    --spatial -c M0_avg.nii.gz --tr=3.58 --cgain=1.0 --cmethod=voxel --te=19 --t2bl=0.15 \
    --fslanat="${anat_dir}" --pvcorr

else
  echo "ERROR: Unknown scanner type. Session must end in 'N' or 'B'."
  exit 1
fi

# === Wrap up ===
echo "Finished ASL processing for $sub_id $ses_id"
ENDTIME=$(date +%s)
Total_time=$(echo "scale=2; ($ENDTIME - $STARTTIME)/3600.0" | bc -l)
echo "Total time: ${Total_time} hours"
