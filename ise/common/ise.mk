###################################################################
# 
# Xilinx ISE FPGA Makefile
# 
# Copyright (c) 2016 Alex Forencich
# Copyright (c) 2025 Hansem Ro
# 
###################################################################
# 
# Parameters:
# FPGA_TOP - Top module name
# FPGA_FAMILY - FPGA family (e.g. Spartan3A)
# FPGA_DEVICE - FPGA device (e.g. xc3s200a-ft256-4)
# SYN_FILES - space-separated list of source files
# INC_FILES - space-separated list of include files
# UCF_FILES - space-separated list of timing constraint files
# XCI_FILES - space-separated list of IP XCI files
# 
# Example:
# 
# FPGA_TOP = fpga
# FPGA_FAMILY = Spartan3A
# FPGA_DEVICE = xc3s200a-ft256-4
# SYN_FILES = rtl/fpga.v
# UCF_FILES = fpga.ucf
# XCI_FILES = ip/pcspma.xci
# include ../common/vivado.mk
# 
###################################################################

# phony targets
.PHONY: fpga ise tmpclean clean distclean

# prevent make from deleting intermediate files and reports
.PRECIOUS: %.ppr %.bit %.mcs %.prm
.SECONDARY:

CONFIG ?= config.mk
-include ../$(CONFIG)

FPGA_TOP ?= fpga
PROJECT ?= $(FPGA_TOP)

SYN_FILES_REL = $(foreach p,$(SYN_FILES),$(if $(filter /% ./%,$p),$p,../$p))
INC_FILES_REL = $(foreach p,$(INC_FILES),$(if $(filter /% ./%,$p),$p,../$p))
XCI_FILES_REL = $(foreach p,$(XCI_FILES),$(if $(filter /% ./%,$p),$p,../$p))
IP_TCL_FILES_REL = $(foreach p,$(IP_TCL_FILES),$(if $(filter /% ./%,$p),$p,../$p))
CONFIG_TCL_FILES_REL = $(foreach p,$(CONFIG_TCL_FILES),$(if $(filter /% ./%,$p),$p,../$p))

ifdef UCF_FILES
  UCF_FILES_REL = $(foreach p,$(UCF_FILES),$(if $(filter /% ./%,$p),$p,../$p))
else
  UCF_FILES_REL = $(PROJECT).ucf
endif

###################################################################
# Main Targets
#
# all: build everything
# clean: remove output files and project files
###################################################################

all: fpga

fpga: $(PROJECT).bit

ise: $(PROJECT).ppr
	planAhead $(PROJECT).ppr

tmpclean::
	-rm -rf *.log *.jou *.cache *.gen *.hbs *.hw *.ip_user_files *.runs *.ppr *.html *.xml *.sim *.srcs *.str .Xil defines.v
	-rm -rf create_project.tcl update_config.tcl run_synth.tcl run_impl.tcl generate_bit.tcl

clean:: tmpclean
	-rm -rf *.bit program.tcl generate_mcs.tcl *.mcs *.prm flash.tcl
	-rm -rf *_utilization.rpt

distclean:: clean
	-rm -rf rev

###################################################################
# Target implementations
###################################################################

# ISE PlanAhead project file
create_project.tcl: Makefile $(XCI_FILES_REL) $(IP_TCL_FILES_REL)
	rm -rf defines.v
	touch defines.v
	for x in $(DEFS); do echo '`define' $$x >> defines.v; done
	echo "create_project -force -part $(FPGA_PART) $(PROJECT)" > $@
	echo "add_files -fileset sources_1 defines.v $(SYN_FILES_REL)" >> $@
	echo "set_property top $(FPGA_TOP) [get_property srcset [current_run]]" >> $@
	echo "add_files -fileset constrs_1 $(UCF_FILES_REL)" >> $@
	for x in $(XCI_FILES_REL); do echo "import_ip $$x" >> $@; done
	for x in $(IP_TCL_FILES_REL); do echo "source $$x" >> $@; done
	for x in $(CONFIG_TCL_FILES_REL); do echo "source $$x" >> $@; done

update_config.tcl: $(CONFIG_TCL_FILES_REL) $(SYN_FILES_REL) $(INC_FILES_REL) $(UCF_FILES_REL)
	echo "open_project -quiet $(PROJECT).ppr" > $@
	for x in $(CONFIG_TCL_FILES_REL); do echo "source $$x" >> $@; done

$(PROJECT).ppr: create_project.tcl update_config.tcl
	planAhead -nojournal -nolog -mode batch $(foreach x,$?,-source $x)

# synthesis+implementation+bitgen run
$(PROJECT).bit: $(PROJECT).ppr $(SYN_FILES_REL) $(INC_FILES_REL) $(UCF_FILES_REL)
	echo "open_project $(PROJECT).ppr" > run_synth_impl.tcl
	echo "reset_run synth_1" >> run_synth_impl.tcl
	echo "launch_runs -jobs 4 synth_1" >> run_synth_impl.tcl
	echo "wait_on_run synth_1" >> run_synth_impl.tcl
	echo "reset_run impl_1" >> run_synth_impl.tcl
	echo "launch_runs -to_step Bitgen -jobs 4 impl_1" >> run_synth_impl.tcl
	echo "wait_on_run impl_1" >> run_synth_impl.tcl
	echo "open_run impl_1" >> run_synth_impl.tcl
	echo "report_utilization -file $(PROJECT)_utilization.rpt" >> run_synth_impl.tcl
	planAhead -nojournal -nolog -mode batch -source run_synth_impl.tcl
	ln -f -s $(PROJECT).runs/impl_1/$(PROJECT).bit .
	mkdir -p rev
	COUNT=100; \
	while [ -e rev/$(PROJECT)_rev$$COUNT.bit ]; \
	do COUNT=$$((COUNT+1)); done; \
	cp -pv $(PROJECT).runs/impl_1/$(PROJECT).bit rev/$(PROJECT)_rev$$COUNT.bit
