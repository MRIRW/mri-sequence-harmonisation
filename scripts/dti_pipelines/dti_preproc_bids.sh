#!/bin/bash

# =========================================================================
# Script: dti_preproc_bids.sh
#
# 📌 Purpose:
# Preprocesses DTI data for the mTBI-Predict study, harmonising diffusion data
# across multiple scanners (Philips, Siemens) and sessions (e.g., A, B, N).
# Applies a unified pipeline using the BIDS structure, performing distortion
# correction (topup), eddy correction, brain extraction, and tensor fitting.
# Shells are not separated; full multi-shell DTI data is processed together.
#
# 📁 Input (BIDS):
#   - DWI:   bids/<sub>/<ses>/dwi/<sub>_<ses>_dwi.nii.gz + .bval/.bvec
#   - Fmap:
#       • For Philips (N): bids/<sub>/<ses>/fmap/<sub>_<ses>_acq-dwi_dir-AP_epi.nii.gz
#       • For Siemens (A/B): bids/<sub>/<ses>/fmap/<sub>_<ses>_acq-dwi_dir-PA_epi.nii.gz
#
# 📤 Output:
#   - derivatives/dti_preproc/<sub>/<ses>/
#
# ⚙️ Dependencies:
#   - FSL, MRtrix3
# =========================================================================

#change the session
sub="sub-0001"
ses="ses-01N"

# === Determine scanner type and set acqparams + directions ===
scanner_type=${ses: -1}
if [[ $scanner_type == "N" ]]; then
  acqdir1="0 1 0 0.0742"
  acqdir2="0 -1 0 0.0742"
elif [[ $scanner_type == "B" ]]; then
  acqdir1="0 -1 0 0.0732608"
  acqdir2="0 1 0 0.0732608"
elif [[ $scanner_type == "A" ]]; then
  acqdir1="0 -1 0 0.0690115"
  acqdir2="0 1 0 0.0690115"
else
  echo "Session ID must end in 'N' or 'B'."
  exit 1
fi

# Write acqparams.txt using detected directions
echo -e "$acqdir1
$acqdir2" > acqparams.txt
STARTTIME=$(date +%s)
echo "Running on $(hostname)"
echo "Started at: $(date +%F_%T)"

# === Paths ===
root_dir=$(pwd)
bids_dir="${root_dir}/bids/${sub}/${ses}"
dwi_dir="${bids_dir}/dwi"
fmap_dir="${bids_dir}/fmap"
out_dir="${root_dir}/derivatives/dti_preproc/${sub}/${ses}"
mkdir -p "$out_dir"
cd "$out_dir" || exit 1

# === Load DWI paths from BIDS directly ===
dwi_img="${dwi_dir}/${sub}_${ses}_dwi.nii.gz"
dwi_bvec="${dwi_dir}/${sub}_${ses}_dwi.bvec"
dwi_bval="${dwi_dir}/${sub}_${ses}_dwi.bval"

# === Extract mean b0 (PA) ===
dwiextract "$dwi_img" -fslgrad bvecs bvals - -bzero | mrmath - mean ${sub}_${ses}_b0_PA.nii.gz -axis 3

# === Reverse b0 depending on scanner ===
if [[ $scanner_type == "N" ]]; then
  mrconvert "${fmap_dir}/${sub}_${ses}_acq-dwi_dir-AP_epi.nii.gz" ${sub}_${ses}_b0_AP.nii.gz
else
  mrconvert "${fmap_dir}/${sub}_${ses}_acq-dwi_dir-PA_epi.nii.gz" ${sub}_${ses}_b0_PA.nii.gz
fi

# === Merge and reorient ===
if [[ $scanner_type == "N" ]]; then
  fslmerge -t ${sub}_${ses}_b0_PAAP ${sub}_${ses}_b0_PA.nii.gz ${sub}_${ses}_b0_AP.nii.gz
else
  fslmerge -t ${sub}_${ses}_b0_APPA ${sub}_${ses}_b0_PA.nii.gz ${sub}_${ses}_b0_AP.nii.gz
fi

fslreorient2std $dwi_img ${sub}_${ses}_dwi_reorient.nii.gz
# === TOPUP ===
if [[ $scanner_type == "N" ]]; then
  topup_input=${sub}_${ses}_b0_PAAP.nii.gz
else
  topup_input=${sub}_${ses}_b0_APPA.nii.gz
fi

fslreorient2std $topup_input ${sub}_${ses}_b0_merged_reoriented.nii.gz

topup --imain=${sub}_${ses}_b0_merged_reoriented.nii.gz --datain=acqparams.txt --config=b02b0.cnf \
      --out=topup_b0 --iout=topup_iout --fout=topup_fout

applytopup --imain=$dwi_img --topup=topup_b0 --datain=acqparams.txt \
           --inindex=1 --method=jac --out=${sub}_${ses}_dwi_topup.nii.gz

# === BET ===
fslmaths topup_iout -Tmean ${sub}_${ses}_b0_mean
bet ${sub}_${ses}_b0_mean.nii.gz ${sub}_${ses}_b0_brain -m -f 0.25

# === EDDY ===
nvols=$(fslval ${sub}_${ses}_dwi_reorient dim4)
echo "Generating index.txt for $nvols volumes"
indx_file=index.txt
rm -f $indx_file
for ((i=1; i<=nvols; i++)); do echo "1" >> $indx_file; done

eddy --imain=${sub}_${ses}_dwi_reorient.nii.gz --mask=${sub}_${ses}_b0_brain_mask.nii.gz \
     --index=$indx_file --acqp=acqparams.txt --bvecs=$dwi_bvec --bvals=$dwi_bval \
     --topup=topup_b0 --out=${sub}_${ses}_dwi_eddy --data_is_shelled

eddy_quad ${sub}_${ses}_dwi_eddy -idx $indx_file -par acqparams.txt \
          -m ${sub}_${ses}_b0_brain_mask.nii.gz -b $dwi_bval

# === Tensor fitting ===
dtifit -k ${sub}_${ses}_dwi_eddy.nii.gz -o ${sub}_${ses}_tensor \
       -m ${sub}_${ses}_b0_brain_mask.nii.gz -r $dwi_bvec -b bvals

# === Save FA and MD maps to TBSS folders ===
mkdir -p ${root_dir}/derivatives/TBSS_analysis/FA
mkdir -p ${root_dir}/derivatives/TBSS_analysis/MD
cp ${out_dir}/${sub}_${ses}_tensor_FA.nii.gz ${root_dir}/derivatives/TBSS_analysis/FA/${sub}_${ses}_FA.nii.gz
cp ${out_dir}/${sub}_${ses}_tensor_MD.nii.gz ${root_dir}/derivatives/TBSS_analysis/MD/${sub}_${ses}_MD.nii.gz


# === Wrap up ===
echo "Finished Philips DTI preprocessing for $sub $ses"
ENDTIME=$(date +%s)
Total_time=$(echo "scale=2; ($ENDTIME - $STARTTIME)/3600.0" | bc -l)
echo "Total time: ${Total_time} hours"
