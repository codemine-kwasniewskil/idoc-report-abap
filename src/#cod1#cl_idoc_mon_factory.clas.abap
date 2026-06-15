"! <p class="shorttext synchronized">IDoc Monitor - factory (composition root)</p>
"! The single place where the monitor object graph is assembled (constructor
"! injection), reusing the existing /COD1/CL_IDOC_SERVICE_FACTORY for the read/
"! action service. Extend the monitor only here.
CLASS /cod1/cl_idoc_mon_factory DEFINITION
  PUBLIC
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS create_facade
      RETURNING VALUE(ro_facade) TYPE REF TO /cod1/cl_idoc_mon_facade.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_factory IMPLEMENTATION.

  METHOD create_facade.
    DATA(lo_service)  = /cod1/cl_idoc_service_factory=>create( ).
    DATA(lo_repo)     = CAST /cod1/if_idoc_mon_repository( NEW /cod1/cl_idoc_mon_repository( ) ).
    DATA(lo_actioncfg) = NEW /cod1/cl_idoc_mon_actioncfg( ).
    DATA(lo_audit)    = NEW /cod1/cl_idoc_mon_audit( ).
    DATA(lo_approval) = NEW /cod1/cl_idoc_mon_approval( lo_audit ).
    DATA(lo_bulk)     = NEW /cod1/cl_idoc_mon_bulk( io_service    = lo_service
                                                    io_repository = lo_repo
                                                    io_actioncfg  = lo_actioncfg
                                                    io_audit      = lo_audit ).

    ro_facade = NEW /cod1/cl_idoc_mon_facade( io_repository = lo_repo
                                              io_actioncfg  = lo_actioncfg
                                              io_audit      = lo_audit
                                              io_approval   = lo_approval
                                              io_bulk       = lo_bulk
                                              io_service    = lo_service ).
  ENDMETHOD.

ENDCLASS.
