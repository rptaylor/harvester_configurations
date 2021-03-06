#!/bin/bash 
#DPB #SBATCH -q debug
#DPB #SBATCH --time 0:30:00
#DPB #SBATCH -q premium
#SBATCH --time 2:00:00
#SBATCH -q regular
#DPB #SBATCH --time 6:00:00
#DPB #SBATCH -q flex
#DPB #SBATCH --time-min=02:00:00
#DPB #SBATCH --time 4:00:00
#SBATCH --image=custom:atlas_athena_21.0.15_DBRelease-31.8.1:latest
#SBATCH --module=cvmfs
#SBATCH -A m2616
#SBATCH -L SCRATCH
#DPB #SBATCH -C haswell
#DPB #SBATCH --cpus-per-task 32
#SBATCH -C knl,quad,cache
#SBATCH --cpus-per-task 136
#SBATCH -N {nNode}

export HARVESTER_WORKER_ID={workerID}
export HARVESTER_ACCESS_POINT={accessPoint}
export HARVESTER_NNODE={nNode}

# export HARVESTER_ACCESS_POINT=/global/cscratch1/sd/mmuskinj/raythena/workdir
# export HARVESTER_WORKDIR=$HARVESTER_ACCESS_POINT
# export HARVESTER_NNODE=$SLURM_NNODES

export HARVESTER_HOME=/global/common/software/atlas/harvester

export PANDA_QUEUE=NERSC_Cori_p2_ES_Test
export container_setup=/release_setup.sh
export HARVESTER_CONTAINER_RELEASE_SETUP_FILE=$container_setup
export pilot_wrapper_bin=/global/common/software/atlas/raythena/runpilot2-wrapper.sh
export pilot_tar_file=/global/common/software/atlas/raythena/pilot2.tar.gz
export HARVESTER_PILOT_CONFIG=/global/common/software/atlas/raythena/default.cfg

# Julien, 02.09.2020 commented out to run extra tests with another raythena version
export SOURCEDIR=/global/common/software/atlas/raythena/ray
# export SOURCEDIR=$SCRATCH/ray
export BINDIR=$SOURCEDIR/bin
export CONFDIR=$SOURCEDIR/conf

export RAYTHENA_HARVESTER_ENDPOINT=$HARVESTER_ACCESS_POINT
export RAYTHENA_RAY_WORKDIR=$HARVESTER_ACCESS_POINT
export RAYTHENA_PAYLOAD_BINDIR=$HARVESTER_ACCESS_POINT
RAYTHENA_RAY_REDIS_PASSWORD=$(uuidgen -r)
export RAYTHENA_RAY_REDIS_PASSWORD
export RAYTHENA_RAY_REDIS_PORT=6379
export RAYTHENA_CONFIG=$CONFDIR/cori.yaml
export RAYTHENA_DEBUG=1
RAYTHENA_RAY_HEAD_IP=$(hostname -i)
export RAYTHENA_RAY_HEAD_IP
export RAYTHENA_PANDA_QUEUE=$PANDA_QUEUE
export NWORKERS=$((HARVESTER_NNODE - 1))
export RAYTHENA_CORE_PER_NODE=$SLURM_CPUS_PER_TASK

cp $pilot_wrapper_bin $RAYTHENA_RAY_WORKDIR
tar xzf $pilot_tar_file -C$RAYTHENA_RAY_WORKDIR

export RAY_TMP_DIR=/tmp/raytmp/$SLURM_JOB_ID

if [[ ! -d $RAY_TMP_DIR ]]; then
  mkdir -p "$RAY_TMP_DIR"
fi

# setup ray
source activate $HARVESTER_HOME

srun -N1 -n1 -w "$SLURMD_NODENAME" $BINDIR/ray_start_head &
pid=$!
retsync=1
try=1
while [[ $retsync -ne 0 ]]; do
  $BINDIR/ray_sync
  retsync=$?
  kill -0 "$pid"
  status=$?
  if [[ $retsync -ne 0 ]] && [[ $status -ne 0 ]]; then
    try=$((try+1))
    if [[ $try -gt 5 ]]; then
      exit 1
    fi
    echo restarting head node init
    srun -N1 -n1 -w "$SLURMD_NODENAME" $BINDIR/ray_start_head &
    pid=$!
  fi
done

srun -x "$SLURMD_NODENAME" -N$NWORKERS -n$NWORKERS $BINDIR/ray_start_worker &
pid=$!
retsync=1
try=1
while [[ $retsync -ne 0 ]]; do
  $BINDIR/ray_sync --wait-workers --nworkers $NWORKERS
  retsync=$?
  kill -0 "$pid"
  status=$?
  if [[ $retsync -ne 0 ]] && [[ $status -ne 0 ]]; then
    try=$((try+1))
    if [[ $try -gt 5 ]]; then
      exit 1
    fi
    echo restarting workers setup
    srun -x "$SLURMD_NODENAME" -N$NWORKERS -n$NWORKERS $BINDIR/ray_start_worker &
    pid=$!
  fi
done

python $SOURCEDIR/app.py

ray stop

if [[ -f core ]]; then
  rm core
fi

wait
