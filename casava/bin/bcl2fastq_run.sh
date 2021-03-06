#!/bin/bash -l

# Check Arguments
MIN_ARGS=5
MAX_ARGS=10
E_BADARGS=65

if [ $# -lt $MIN_ARGS ] || [ $# -gt $MAX_ARGS ]; then
  echo "Usage: `basename $0` {FlowcellID} {RunDirectoryName} {BaseMask} {SampleSheet} {Mismatch, default=1} {NoSplit} [ExtraFlag]"
  exit $E_BADARGS
fi

# Get args
fc_id=$1
run_dir=$2
base_mask=$3
sample_sheet=$4
barcode_mismatch=$5
extra_flag="$7"

if [[ $# -gt 7 ]]; then 
    for (( i = 8; i <= $#; i++ )); do
        extra_flag="${extra_flag} ${$i}"
    done
fi

if [[ "$6" == "nosplit" ]]; then
    lane_split="--no-lane-splitting"
else
    lane_split=""
fi
    
module load bcl2fastq
cd $SHARED_GENOMICS/RunAnalysis/flowcell$fc_id
echo "Creating output directory..."
mkdir -p $SHARED_GENOMICS/$fc_id/$run_dir
echo "Running bcl2fastq for demultiplexing..."

if [[ ! "${base_mask}" == "NA" ]]; then
    echo -e "\tRunning with BaseMask ${base_mask}"
    bcl2fastq --use-bases-mask $base_mask --runfolder-dir=$run_dir --sample-sheet=$sample_sheet --barcode-mismatches=$barcode_mismatch --minimum-trimmed-read-length 0 --mask-short-adapter-reads 0 --ignore-missing-bcls --ignore-missing-filter --ignore-missing-positions --ignore-missing-controls $lane_split --processing-threads=64 --demultiplexing-threads=12 --loading-threads=4 --writing-threads=4 ${extra_flag} --output-dir=$SHARED_GENOMICS/$fc_id/$run_dir 2>&1 | tee $SHARED_GENOMICS/$fc_id/nohup.out
else
    echo -e "\tRunning with out BaseMask"
    bcl2fastq --runfolder-dir=$run_dir --sample-sheet=$sample_sheet --barcode-mismatches=$barcode_mismatch --ignore-missing-bcls --ignore-missing-filter --ignore-missing-positions --ignore-missing-controls $lane_split --processing-threads=64 --demultiplexing-threads=12 --loading-threads=4 --writing-threads=4 ${extra_flag} --output-dir=$SHARED_GENOMICS/$fc_id/$run_dir 2>&1 | tee $SHARED_GENOMICS/$fc_id/nohup.out
fi

