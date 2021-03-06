#!/bin/bash -l

#############################################
# Check for HiSeq data and execute pipeline #
#############################################

# Set global vars
set -e
source $HTS_PIPELINE_HOME/env_profile.sh
ERROR=0

# Check Arguments
EXPECTED_ARGS=4
E_BADARGS=65

SHORT=f:d:m:Db:P:
LONG=flowcell:,dir:,mismatch:,dev,password-protect:,base-mask:

PARSED=$(getopt --options $SHORT --longoptions $LONG --name "$0" -- "$@")

if [[ $? -ne 0 ]]; then
    exit 2
fi
eval set -- "$PARSED"

while true; do
    case "$1" in
        -b|--base-mask)
            # Does nothing with it
            BASE_MASK="$2"
            shift 2
            ;;
        -P|--password-protect)
            # Does nothing with it
            PASSWORD_PROTECT="$2"
            shift 2
            ;;
        -D|--dev)
            DEV=y
            shift
            ;;
        -f|--flowcell)
            FC_ID="$2"
            shift 2
            ;;
        -d|--dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        -m|--mismatch)
            MISMATCH="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

SEQ="hiseq"
if [[ -z "$MISMATCH" ]]; then
    MISMATCH=1
fi

# Change directory to source
cd $SOURCE_DIR

# Check for SampleSheet
complete_file=`find $SOURCE_DIR -name RTAComplete.txt`

if [ -f $complete_file ]; then
    # Determine sequencer run directory
    run_dir=`dirname $complete_file`
    dir=`dirname $run_dir`
    run_dir=`basename $run_dir`
    lockfile="${SEQ}_start.lock"
 
    # Set lock file
    if [[ ! "$(cat $lockfile)" == "${SLURM_JOBID}" ]]; then
        echo -e "ERROR: JOB ID does not match"
        ERROR=1 && exit 1
    fi

    # Set error file
    export ERROR_FILE=$SHARED_GENOMICS/$FC_ID/error.log
    mkdir -p $SHARED_GENOMICS/$FC_ID
    echo "Starting Pipeline" > $ERROR_FILE
    
    ##################
    # Pipeline Steps #
    ##################

    # Create SampleSheet_DB.csv
    CMD="create_original_samplesheet_hiseq.R $FC_ID"
    echo -e "==== Create Samplesheet ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then
        ${CMD} &>> $ERROR_FILE
        if [ $? -ne 0 ]; then
            echo "ERROR:: Samplesheet creation failed" >> $ERROR_FILE && ERROR=1
        fi
    fi

    # Create copy of the original samplesheet from Clay and name it as SampleSheet.csv
    samplesheet_origfile=$(ls ${SHARED_GENOMICS}/Runs/$run_dir/*_FC#*.csv)
    CMD="cp $samplesheet_origfile SampleSheet.csv"
    echo -e "==== Create copy of the original samplesheet from Clay STEP ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then
        ${CMD} &>> $ERROR_FILE
        if [ $? -ne 0 ]; then
            echo "ERROR:: Create copy of original samplesheet failed" >> $ERROR_FILE && ERROR=1
        fi
    fi

    # Transfer sequence data
    CMD="transfer_data.sh $FC_ID $SOURCE_DIR"
    echo -e "==== Transfer STEP ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then
        ${CMD} &>> $ERROR_FILE
        if [ $? -ne 0 ]; then
            echo "ERROR:: Transfer failed" >> $ERROR_FILE && ERROR=1
        fi
    fi
        
    # Check if SampleSheet.csv exists
    echo -e "==== SAMPLESHEET CHECK STEP ====\n" >> $ERROR_FILE
    if [[ ! -f ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$run_dir/SampleSheet.csv ]]; then
        echo "ERROR:: SampleSheet from ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$run_dir/SampleSheet.csv does not exist" >> $ERROR_FILE && ERROR=1
    else
        # Create SampleSheet_rename and QC from SampleSheet.
        CMD="create_samplesheet_${SEQ}.R ${FC_ID} ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$run_dir/SampleSheet.csv $run_dir"
        echo -e "==== SAMPLE SHEET STEP ====\n${CMD}" >> $ERROR_FILE
        if [ $ERROR -eq 0 ]; then
            ${CMD} &>> $ERROR_FILE
            if [ $? -ne 0 ]; then
                echo "ERROR:: SampleSheet_rename creation failed" >> $ERROR_FILE && ERROR=1
            fi
        fi
    fi 

    #Copy SampleSheet from RunAnalysis
    cp ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$run_dir/SampleSheet.csv ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv 
    #cp ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv ${SHARED_GENOMICS}/${FC_ID}/SampleSheet_rename.csv

    # Create Sample Sheet for demux
    if [ $ERROR -eq 0 ]; then
        numpair=$(( $(ls ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$run_dir/Basecalling_Netcopy_complete_Read*.txt | wc -l) - 1 ))
        NUMFILES=$numpair
        MUX=1
        BASEMASK="NA"
        date=$(date +"%m/%d/%Y")
        numcycles=$(( $(ls ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$run_dir/Logs | grep -oP "[0-9]+\.log$" | cut -d. -f1 | sort -n | tail -1) - 1 ))
        if [ $numpair > 1 ]; then
            cycles=$(echo -e "${numcycles},\n${numcycles},\n")
        else
            cycles=$(echo -e "${numcycles},\n")
        fi

    #cat << EOF > ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv 
#[Header]
#IEMFileVersion,4
#Investigator Name,Neerja Katiyar
#Experiment Name,350
#Date,${date}
#Workflow,GenerateFASTQ
#Application,HiSeq FASTQ Only
#Assay,TruSeq Small RNA
#Description,human small rna
#Chemistry,Default

#[Reads]
#${cycles}

#[Settings]
#ReverseComplement,0

#[Data]
#Lane,Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description
#EOF
    
        #grep -P "^${LABEL}" ${SHARED_GENOMICS}/${FC_ID}/SampleSheet_rename.csv | awk -F ',' '{print $2","$3",,,,,"$5","$10","}' >> ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv
        #barcode=$(grep -P "^${LABEL}" ${SHARED_GENOMICS}/${FC_ID}/SampleSheet_rename.csv | awk -F ',' '{$5}' | head -1)
    fi

  
    # Extract a barcode to calculate barcode length
    #barcode=$(tail -1 ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv | awk '{split($0,a,","); print a[7]}')

    # Extract a barcode from every lane to calculate barcode length per lane
    LANE_NUM=(0 0 0 0 0 0 0 0 0)
    DATA=$(cat ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv | sed '1,/Lane/d')
    while IFS='' read -r line || [[ -n "$line" ]]
    do
        lane=$(echo $line | cut -d, -f1) 
        barcode=$(echo $line | awk '{split($0,a,","); print a[7]}' | sed 's/[^a-zA-Z0-9]//g')
        if [ ${LANE_NUM[$lane]} == 0 ] ; then
            LANE_NUM[$lane]=${#barcode}
        fi
    done <<< "$(echo -e "$DATA")"

    # Create the basemask per lane
    INDEX=1
    NO_LANES=0
    BASEMASK=""
    for i in ${LANE_NUM[@]:1}; do
        if [ "${i}" == "0" ]; then
            INDEX=$(($INDEX+1))
            NO_LANES=1
            continue;
        fi
        if [ ${numpair} == 1 ]; then
            BASEMASK="$BASEMASK $INDEX:Y*,I${i}n"
        elif [ ${numpair} == 2 ]; then
            BASEMASK="$BASEMASK $INDEX:Y*,I${i}n,Y*"
        fi
        if [ $INDEX != 8 ]; then
            BASEMASK="$BASEMASK --use-bases-mask"
        fi
        NO_LANES=0
        INDEX=$(($INDEX+1))
    done
    
    # We will demultiplex and barcode is of standard length 6 (single-end,paired-end)
    #if [[ ${#barcode} == 6 ]]; then
    if [ ${LANE_NUM[1]} != 0 ]; then
        MUX=1
        #We will demultiplex and the barcode is of different length and single-end
        if [ ${LANE_NUM[1]} > 6 ] && [ ${numpair} == 1 ]; then
            NUMFILES=1
        fi
    elif [ ${LANE_NUM[1]} == 0 ]; then
        MUX=2
        #User demultiplexes and it is single end
        if [ ${numpair} == 1 ]; then
            NUMFILES=2
        #User will demultiplex and it is paired-end
        elif [ ${numpair} == 2 ]; then
            NUMFILES=3
        fi
        
    fi
    
    #Remove --use-bases-mask if the last lane does not have a basemask
    if [ $NO_LANES -eq 1 ]; then
        if [ "$BASEMASK" !=  "" ]; then
            BASEMASK=${BASEMASK::-16}
        else
            if [ ${numpair} == 1 ]; then
                BASEMASK="Y*,Y*"
            elif [ ${numpair} == 2 ]; then
                BASEMASK="Y*,Y*,Y*"
            fi
        fi
    fi

    #We will demultiplex and the barcode is of different length and single-end
    #if [ ${#barcode} > 6 ] && [ ${numpair} == 1 ]; then
        #MUX=1
        #BASEMASK="Y*,I${#barcode},Y*"
        #NUMFILES=1
    #fi
    
    #User demultiplexes and it is single end
    #if [ ${numpair} == 1 ] && [ ${#barcode} == 0 ]; then
        #MUX=2
        #BASEMASK="Y*,Y*"
        #NUMFILES=2
    #fi

    #User will demultiplex and it is paired-end
    #if [ ${numpair} == 2 ] && [ ${#barcode} == 0 ]; then
       #MUX=2
       #BASEMASK="Y*,Y*,Y*"
       #NUMFILES=3 
    #fi
    
    # We demux
    CMD="bcl2fastq_run.sh ${FC_ID} $run_dir "${BASEMASK:-NA}" ${SHARED_GENOMICS}/${FC_ID}/SampleSheet.csv 1 ''"
    echo -e "==== DEMUX STEP ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then
        cd $SHARED_GENOMICS/$FC_ID
        eval ${CMD} &> nohup.out
        if [ $? -ne 0 ]; then
            echo "ERROR:: Demuxing failed" >> $ERROR_FILE && ERROR=1
        fi
    fi
    

    # Rename Files
    CMD="fastqs_rename.R $FC_ID ${NUMFILES} ${SHARED_GENOMICS}/${FC_ID}/SampleSheet_rename.csv $run_dir ${SEQ} $run_dir"
    echo -e "==== RENAME STEP ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then 
        ${CMD} &>> $ERROR_FILE
        if [ $? -ne 0 ]; then 
            echo "ERROR: Files rename failed" >> $ERROR_FILE && ERROR=1
        fi
    fi
    
    # Generate QC report
    CMD="qc_report_generate_targets.R $FC_ID ${numpair} $SHARED_GENOMICS/$FC_ID/ $SHARED_GENOMICS/$FC_ID/fastq_report/ $SHARED_GENOMICS/$FC_ID/SampleSheet_rename.csv $MUX"
    echo -e "==== QC STEP ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then
        ${CMD} &>> $ERROR_FILE
        if [ $? -ne 0 ]; then
            echo "ERROR: QC report generation failed" >> $ERROR_FILE && ERROR=1
        fi
    fi

    # Generate 2nd QC report for individual lanes
    CMD="generate_fastqc_report.sh $FC_ID 8"
    echo -e "==== SECOND QC STEP ====\n${CMD}" >> $ERROR_FILE
    if [ $ERROR -eq 0 ]; then
    	${CMD} &>> $ERROR_FILE
        if [ $? -ne 0 ]; then
            echo "ERROR: FastQC report generation failed" >> $ERROR_FILE && ERROR=1
        fi
    fi
   
    # Update Illumina web server URLs
	if [[ "$DEV" != "y" ]]; then
		CMD="sequence_url_update.R $FC_ID 1 $SHARED_GENOMICS/$FC_ID"
		echo -e "==== URL STEP ====\n${CMD}" >> "$ERROR_FILE"
		if [ $ERROR -eq 0 ]; then
			${CMD} &>> "$ERROR_FILE"
			if [ $? -ne 0 ]; then
				echo "ERROR: Illumina URL update failed" >> "$ERROR_FILE" && ERROR=1
			fi
		fi
	else
    	echo "URL Step skipped (in dev mode)" >> "$ERROR_FILE"
	fi
   
	 
	# Remove lock files
    rm -f ${SHARED_GENOMICS}/RunAnalysis/flowcell${FC_ID}/$lockfile
fi

# Exit
exit $ERROR

