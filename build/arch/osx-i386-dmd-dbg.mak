include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-g -debug -version=SuspendOneAtTime -version=mpi -version=NoFix
# -version=DetailedLog -version=NoReuse -version=TrackQueues
CFLAGS_COMP=-g
