"! <p class="shorttext synchronized">IDoc Monitor - signature (value object)</p>
"! Computes the stable signature key from the composing fields
"! (direction | messageType | status | messageId | messageNumber), hashed to a
"! 32-char hex key - byte-parity with the BTP signature engine. Instance
"! variables are deliberately EXCLUDED (they are instance data, not a pattern).
CLASS /cod1/cl_idoc_mon_signature DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Stable 32-char signature key.
    CLASS-METHODS compute
      IMPORTING iv_direct     TYPE edidc-direct
                iv_mestyp     TYPE edidc-mestyp
                iv_status     TYPE edidc-status
                iv_stamid     TYPE edids-stamid
                iv_stamno     TYPE edids-stamno
      RETURNING VALUE(rv_key) TYPE /cod1/idoc_sig-sig_key.

    "! Human-readable description of a signature (for the dashboard).
    CLASS-METHODS describe
      IMPORTING iv_direct      TYPE edidc-direct
                iv_mestyp      TYPE edidc-mestyp
                iv_status      TYPE edidc-status
                iv_stamid      TYPE edids-stamid
                iv_stamno      TYPE edids-stamno
      RETURNING VALUE(rv_text) TYPE /cod1/idoc_sig-text.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_signature IMPLEMENTATION.

  METHOD compute.
    DATA lv_hash TYPE hash160_hex.
    DATA(lv_canonical) = |{ iv_direct }\|{ iv_mestyp }\|{ iv_status }\|{ iv_stamid }\|{ iv_stamno }|.

    CALL FUNCTION 'CALCULATE_HASH_FOR_CHAR'
      EXPORTING  data           = lv_canonical
      IMPORTING  hash           = lv_hash
      EXCEPTIONS no_data        = 1
                 OTHERS         = 2.
    IF sy-subrc = 0.
      rv_key = lv_hash(32).                       "first 32 hex chars of the SHA1
    ELSE.
      rv_key = lv_canonical.                       "fallback (truncated to field length)
    ENDIF.
  ENDMETHOD.

  METHOD describe.
    DATA(lv_dir) = COND string( WHEN iv_direct = '2' THEN 'IN' ELSE 'OUT' ).
    rv_text = |{ lv_dir } { iv_mestyp } st { iv_status } { iv_stamid }/{ iv_stamno }|.
  ENDMETHOD.

ENDCLASS.
