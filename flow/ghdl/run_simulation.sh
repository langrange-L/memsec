#!/bin/bash
#
# MEMSEC - Framework for building transparent memory encryption and authentication solutions.
# Copyright (C) 2017-2018 Graz University of Technology, IAIK <mario.werner@iaik.tugraz.at>
#
# This file is part of MEMSEC.
#
# MEMSEC is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# MEMSEC is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with MEMSEC.  If not, see <http://www.gnu.org/licenses/>.
#
shopt -s expand_aliases
PWD=$(pwd)
DATE=$(date)

# define the log command which writes to the logfile and possibly to stdout
if [ ${FLOW_VERBOSITY} -ge 2 ]; then
  alias log='tee -a "${FLOW_LOG_FILE}"'
else
  alias log='cat >> "${FLOW_LOG_FILE}"'
fi

echo "" >> "${FLOW_LOG_FILE}"
echo "###############################################################################" >> "${FLOW_LOG_FILE}"
echo "# ${DATE}" >> "${FLOW_LOG_FILE}"
echo "###############################################################################" >> "${FLOW_LOG_FILE}"
echo "\$ cd ${PWD}" 2>&1 | log

if [ -z "${FLOW_SIM_TOP}" ]; then
  echo "No top module defined. Simulation not possible!"
  exit 1
fi

# add the directories of all dependencies to the compile options
GHDL_COMPILE_OPTIONS="${FLOW_GHDL_CFLAGS}"
for I in ${FLOW_FULL_DEPENDENCY_DIRS}
do
  GHDL_COMPILE_OPTIONS="${GHDL_COMPILE_OPTIONS} -P${I}"
done

# Analyse and elaborate the design
echo "\$ ${FLOW_GHDL_BINARY} -m ${GHDL_COMPILE_OPTIONS} ${FLOW_SIM_TOP}" 2>&1 | log
${FLOW_GHDL_BINARY} -m ${GHDL_COMPILE_OPTIONS} ${FLOW_SIM_TOP} 2>&1 | log
RETURN_VALUE=${PIPESTATUS[0]}
if [ $RETURN_VALUE -ne "0" ]; then
  exit $RETURN_VALUE
fi

# generate the ghdl command line flags
GHDL_RUN_OPTIONS="${FLOW_GHDL_RFLAGS} --stop-time=${FLOW_SIM_TIME}"
if [ "1" = "${FLOW_GTKWAVE_GUI}" ] || [ "1" = "${FLOW_WRITE_GHW}" ]; then
  GHDL_RUN_OPTIONS="${GHDL_RUN_OPTIONS} --wave=${FLOW_SIM_TOP}.ghw"
fi
if [ "1" = "${FLOW_WRITE_VCD}" ]; then
  GHDL_RUN_OPTIONS="${GHDL_RUN_OPTIONS} --vcd=${FLOW_SIM_TOP}.vcd"
fi

case ${FLOW_SIM_RESULT_RULE} in
  file-*)
  # set the result file to the log file if it is undefined
  if [ -z "${FLOW_SIM_RESULT_FILE}" ]; then
    FLOW_SIM_RESULT_FILE="${FLOW_MODULE}_${FLOW_SIM_TOP}_latest_simulation.log"
  fi
  # delete the result file if it is used and already exists
  if [ -f ${FLOW_SIM_RESULT_FILE} ]; then
    echo "\$ rm ${FLOW_SIM_RESULT_FILE}" 2>&1 | log
    rm ${FLOW_SIM_RESULT_FILE} 2>&1 | log
  fi
  ;;
esac

# convert the generics into ghdl options
GENERICS=$(env | grep -e "^GENERIC_" | xargs)
for I in ${GENERICS}
do
  GHDL_RUN_OPTIONS="${GHDL_RUN_OPTIONS} -g${I#GENERIC_}"
done

# run the simulation
echo "\$ ${FLOW_GHDL_BINARY} -r ${GHDL_COMPILE_OPTIONS} ${FLOW_SIM_TOP} ${GHDL_RUN_OPTIONS}" 2>&1 | log
${FLOW_GHDL_BINARY} -r ${GHDL_COMPILE_OPTIONS} ${FLOW_SIM_TOP} ${GHDL_RUN_OPTIONS} 2>&1 | tee "${FLOW_MODULE}_${FLOW_SIM_TOP}_latest_simulation.log" | log
RETURN_VALUE=${PIPESTATUS[0]}
if [ $RETURN_VALUE -ne "0" ] && [ "sim-return" = "${FLOW_SIM_RESULT_RULE}" ]; then
  echo "RESULT: Simulation failed. Simulator exited with return value \"${RETURN_VALUE}\"." 2>&1 | log
  exit $RETURN_VALUE
fi

# determine the exit code of the simulation
case ${FLOW_SIM_RESULT_RULE} in
  file-success)
  EXIT_CODE=1
  # check if the result file exists and check its contents
  if [ -f ${FLOW_SIM_RESULT_FILE} ]; then
    COMP=$(cat "${FLOW_SIM_RESULT_FILE}" | grep -Eq  "${FLOW_SIM_RESULT_REGEX}"; echo $?)
    if [ $COMP -eq "0" ]; then
      echo "RESULT: Simulation succeeded." 2>&1 | log
      EXIT_CODE=0
    else
      echo "RESULT: Simulation failed." 2>&1 | log
    fi
  else
    echo "RESULT: Timeout. Result file \"${FLOW_SIM_RESULT_FILE}\" not found." 2>&1 | log
    EXIT_CODE=2
  fi
  ;;

  file-failure)
  EXIT_CODE=0
  # check if the result file exists and check its contents
  if [ -f ${FLOW_SIM_RESULT_FILE} ]; then
    COMP=$(cat "${FLOW_SIM_RESULT_FILE}" | grep -Eq  "${FLOW_SIM_RESULT_REGEX}"; echo $?)
    if [ $COMP -eq "0" ]; then
      echo "RESULT: Simulation failed." 2>&1 | log
      EXIT_CODE=1
    else
      echo "RESULT: Simulation succeeded." 2>&1 | log
    fi
  else
    echo "RESULT: Timeout. Result file \"${FLOW_SIM_RESULT_FILE}\" not found." 2>&1 | log
    EXIT_CODE=2
  fi
  ;;

  sim-return)
  ;;

  *)
  echo "ERROR: unsupported RESULT_RULE '${FLOW_SIM_RESULT_RULE}' used" 2>&1 | log
  EXIT_CODE=1
  ;;
esac

# launch gtkwave if requested
if [ "1" = "${FLOW_GTKWAVE_GUI}" ]; then
  if [ "" = "${FLOW_GTKWAVE_BINARY}" ]; then
    echo "" 2>&1 | log
    echo "ERROR: gtkwave has not been found, consider opening the ghw file manually" 2>&1 | log
    echo "ERROR: ghw-file: ${FLOW_BINARY_DIR}/${FLOW_SIM_TOP}.ghw" 2>&1 | log
    echo "" 2>&1 | log
  else
    GTKWAVE_RUN_OPTIONS="${FLOW_SIM_TOP}.ghw"
    if [ -f "${FLOW_SIM_TOP}.sav" ]; then
      GTKWAVE_RUN_OPTIONS="${GTKWAVE_RUN_OPTIONS} ${FLOW_SIM_TOP}.sav"
    fi
    if [ -f "${FLOW_SIM_TOP}.gtkw" ]; then
      GTKWAVE_RUN_OPTIONS="${FLOW_SIM_TOP}.gtkw"
    fi

    echo "\$ ${FLOW_GTKWAVE_BINARY} ${GTKWAVE_RUN_OPTIONS} &" 2>&1 | log
    ${FLOW_GTKWAVE_BINARY} ${GTKWAVE_RUN_OPTIONS} 2>&1 | log &
  fi
fi

exit ${EXIT_CODE}
