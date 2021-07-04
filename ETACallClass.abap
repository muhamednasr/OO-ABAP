class ZETA_API_CALL definition
  public
  final
  create public .

public section.

  methods FETCH_DOCUMENT_TYPES
    importing
      !TOKEN type STRING
    exporting
      !STATUS type STRING .
  methods TOKEN_EXTRACTION
    exporting
      !TOKEN type STRING
      !STATUS type STRING .
  methods DOCS_SUBMISSION
    importing
      !JSON_DATA type STRING
      !TOKEN type STRING
    exporting
      !REJECTEDDOCS type ZREJECTED_DOCUMENTS
      !RESPONSE type STRING
      !STATUS type STRING
      !UUIDS type ZTETA_DOC_SUB .
  methods DOCS_CANCEL
    importing
      !TOKEN type STRING
      !UUID type STRING
    exporting
      !STATUS type STRING
      !CANCEL_STATUS type STRING
    exceptions
      CANCEL_REJECTED
      CANCEL_NOT_FOUND .
  class-methods SERIALIZE_TO_JSON
    importing
      !DATA type ANY
    exporting
      !JSON_DATA type STRING .
  class-methods DESERIALIZE_TO_ABAP
    importing
      !BODY type STRING
    exporting
      !DATA type DATA .
  class-methods MOCK_DATA
    exporting
      !DATA type ZST_ETA_DATA .
  methods GET_SUBMIT_STATUS
    importing
      !UUID type STRING
      !TOKEN type STRING
    exporting
      !BILL_STATUS type STRING
      !STATUS type STRING
      !ERROR_MESSAGES type ZTINNERERROR .
  methods CALL_LOCAL_SIGNATURE_API
    importing
      !JSON_DATA type STRING
    exporting
      !SIGNED_DATA type STRING .
protected section.
private section.

  types:
    begin of head,

          name    type IHTTPNAM,
          value   type IHTTPVAL,

        end of head .

  data LO_HTTP_CLIENT type ref to IF_HTTP_CLIENT .
  data LO_REST_CLIENT type ref to CL_REST_HTTP_CLIENT .
  data LV_URL type STRING .
  data HTTP_STATUS type STRING .
  data LV_BODY type STRING .
  data LO_JSON type ref to CL_CLB_PARSE_JSON .
  data LO_RESPONSE type ref to IF_REST_ENTITY .
  data LO_REQUEST type ref to IF_REST_ENTITY .
  data LO_SQL type ref to CX_SY_OPEN_SQL_DB .
  data STATUS type STRING .
  data REASON type STRING .
  data RESPONSE type STRING .
  data CONTENT_LENGTH type STRING .
  data LOCATION type STRING .
  data CONTENT_TYPE type STRING .
  data LV_TOKEN type STRING .
  data HEADER_TOKEN type STRING .
  data LV_STATUS type I .
  data BODY type STRING .
  data RESP_DATA type ref to DATA .
  data USERNAME type STRING .
  data PASSWORD type STRING .
  data WA_HEADER_CONFIG type HEAD .
  data IT_HEADER_CONFIG type TIHTTPNVP .
ENDCLASS.

CLASS ZETA_API_CALL IMPLEMENTATION.

method CALL_LOCAL_SIGNATURE_API.

  clear : lv_url,body.

  data: lo2_http_client type ref to IF_HTTP_CLIENT,
        lo_request type ref to IF_HTTP_REQUEST,
        lo_response type ref to IF_HTTP_RESPONSE.

  data: resp type ZSETA_SUB_RESPONSE,
        docs type ZETA_DOC_SUB.

  SELECT SINGLE VALUE
      FROM ZETA_PARAMS
       INTO LV_URL
        WHERE PKEY = 'SIGNATURE_API'.

*  making HTTP client instance
  cl_http_client=>create_by_url(
       EXPORTING
         url                = lv_url
       IMPORTING
         client             = lo2_http_client
       EXCEPTIONS
         argument_not_found = 1
         plugin_not_active  = 2
         internal_error     = 3
         OTHERS             = 4 ).

   lo2_http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).
   lo2_http_client->request->set_method( if_http_request=>co_request_method_post ).

   lo2_http_client->REQUEST->SET_CDATA( json_data ).

    lo2_http_client->SEND( ).

    BREAK-POINT.

    call method lo2_http_client->receive
      exceptions
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3.
    if sy-subrc ne 0.

    endif.

    data: lv_ret_code type i,
          lv_err_string type string.

   lo2_http_client->response->get_status(
      importing
        code   = lv_ret_code
        reason = lv_err_string
           ).

  signed_data = lo2_http_client->RESPONSE->GET_CDATA( ).

endmethod.

  method DESERIALIZE_TO_ABAP.

  CALL METHOD /ui2/cl_json=>deserialize
    EXPORTING
      json         = body
      pretty_name  = /ui2/cl_json=>pretty_mode-camel_case
      assoc_arrays = abap_true
    CHANGING
      data         = data.

  endmethod.

  method DOCS_CANCEL.
     data: lv_url   type string,
          lv_data   type string,
          json_data type string,
          body type ZCANCEL_REQUEST_BODY.

    data: validation_steps type ZSVALIDATIONSTEPS.
    clear: lo_http_client,lo_rest_client,lo_response,lo_request, lv_url,body.

    concatenate 'https://api.preprod.invoicing.eta.gov.eg/api/v1.0/documents/state/' UUID '/state' into lv_url.

*making HTTP client instance
cl_http_client=>create_by_url(
     EXPORTING
       url                = lv_url
     IMPORTING
       client             = lo_http_client
     EXCEPTIONS
       argument_not_found = 1
       plugin_not_active  = 2
       internal_error     = 3
       OTHERS             = 4 ).

*making REST client
CREATE OBJECT lo_rest_client
     EXPORTING
       io_http_client = lo_http_client.

   lo_http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).

*creating request instance
lo_request = lo_rest_client->if_rest_client~create_request_entity( ).

select pkey value
  from ZETA_H_CONFIG
   into table it_HEADER_CONFIG
    where api = 'SUBMISSION'.

  WA_HEADER_CONFIG-name  = 'Authorization'.
  WA_HEADER_CONFIG-value = token.
  append wa_header_config to it_header_config.

*SET header Data.
CALL METHOD lo_request->set_header_fields
  EXPORTING
   IT_HEADER_FIELDS = it_header_config.

body-status  = 'cancelled'.
body-reason  = 'test canceling'.

CALL METHOD zeta_api_call=>serialize_to_json
  EXPORTING
    DATA   = body
  IMPORTING
    json_data   = json_data .

lo_request->set_string_data( json_data ).

*Put method
lo_rest_client->if_rest_resource~put( lo_request ).

** Collect response
lo_response = lo_rest_client->if_rest_client~get_response_entity( ).
status = lv_status = lo_response->get_header_field( '~status_code' ).
response =  lo_response->GET_STRING_DATA( ).

clear resp_data.
CALL METHOD zeta_api_call=>deserialize_to_abap
  EXPORTING
    body   = response
  IMPORTING
    data   = lv_data .

   case status.
     when  200.
      if lv_data = 'true'.
          cancel_status = 'true'.
      else.
          cancel_status = 'false'.
      endif.
     when 400.
       raise CANCEL_REJECTED.
     when 404.
       raise CANCEL_NOT_FOUND.

  endcase.

  endmethod.

  method DOCS_SUBMISSION.

clear: lo_http_client,lo_rest_client,lo_response,lo_request, lv_url,body.

data: resp type ZSETA_SUB_RESPONSE,
      docs type ZETA_DOC_SUB,
      accepted_docs type ZSACCEPTED_DOCUMENTS,
      rejected_docs type ZSREJECTED_DOCUMENTS,
      local_api_data type String,
      Signed_DATA type string.

SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO LV_URL
      WHERE PKEY = 'SUBMISSION_URL'.

*making HTTP client instance
cl_http_client=>create_by_url(
     EXPORTING
       url                = lv_url
     IMPORTING
       client             = lo_http_client
     EXCEPTIONS
       argument_not_found = 1
       plugin_not_active  = 2
       internal_error     = 3
       OTHERS             = 4 ).

*making REST client
CREATE OBJECT lo_rest_client
     EXPORTING
       io_http_client = lo_http_client.

   lo_http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).

              CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
                EXPORTING
                  PERCENTAGE = 70
                  TEXT       = 'Calling ETA Service'.

*creating request instance
lo_request = lo_rest_client->if_rest_client~create_request_entity( ).

select pkey value
  from ZETA_H_CONFIG
   into table it_HEADER_CONFIG
    where api = 'SUBMISSION'.

  WA_HEADER_CONFIG-name  = 'Authorization'.
  WA_HEADER_CONFIG-value = token.
  append wa_header_config to it_header_config.

*SET header Data.
CALL METHOD lo_request->set_header_fields
  EXPORTING
   IT_HEADER_FIELDS = it_header_config.


"""""""" calling local signature API to sign data
clear LV_URL.
DATA: lo2_http_client type ref to cl_http_client.

SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO LV_URL
      WHERE PKEY = 'SIGNATURE_API'.

*making HTTP client instance
**_________________________________________________________________________*

   local_api_data = JSON_DATA.
   CALL_LOCAL_SIGNATURE_API( exporting JSON_DATA = local_api_data
                             IMPORTING SIGNED_DATA = SIGNED_DATA ).

*_________________________________________________________________________*

*Passing data to request body
 lo_request->set_string_data( SIGNED_DATA ).
*lo_request->set_string_data( JSON_DATA ).

*Post method
lo_rest_client->if_rest_resource~post( lo_request ).

** Collect response
lo_response = lo_rest_client->if_rest_client~get_response_entity( ).
status = lv_status = lo_response->get_header_field( '~status_code' ).
response =  lo_response->GET_STRING_DATA( ).

clear resp_data.
CALL METHOD zeta_api_call=>deserialize_to_abap
  EXPORTING
    body   = response
  IMPORTING
    data   =  resp .

  case status.
    when 202.
*       if resp-submissionid is not initial.
         loop at resp-ACCEPTEDDOCUMENTS into accepted_docs.
            docs-uuid = accepted_docs-uuid.
            docs-billing = accepted_docs-INTERNALID.
            append docs to uuids.
            clear: accepted_docs, docs.
         endloop.

         loop at resp-rejectedDocuments into rejected_docs.
            docs-billing = rejected_docs-INTERNALID.
            append docs to uuids.
            clear: accepted_docs, docs.
         endloop.
       REJECTEDDOCS = resp-rejectedDocuments.
     endcase.

  endmethod.

  method FETCH_DOCUMENT_TYPES.
clear: lo_http_client,lo_rest_client,lo_response,lo_request, lv_url,body,resp_data.

DATA: wa_DOCS TYPE ZETA_DOC_TYPE_1,
      it_DOCS TYPE standard table of ZETA_DOC_TYPE_1.

FIELD-SYMBOLS:  <data>        TYPE data,
                <results>     TYPE any,
                <structure>   TYPE any,
                <table>       TYPE any table,
                <DOC_VER>     type any,
                <DOC_VER_T>   type any table,
                <results_ver> type data,
                <field>       TYPE data,
                <fieldvalue>       TYPE data,
                <field_ID>    TYPE any,
                <VER_ID>      type data,
                <VER_TYPE>      type data,
                <VER_NUMBER>      type data,
                <VER_NAME>      type data,
                <VER_DESC>      type data,
                <field_name>    TYPE data,
                <field_desc>    TYPE data.

SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO LV_URL
      WHERE PKEY = 'FETCH_DOCS_URL'.

*making HTTP client instance
cl_http_client=>create_by_url(
     EXPORTING
       url                = lv_url
     IMPORTING
       client             = lo_http_client
     EXCEPTIONS
       argument_not_found = 1
       plugin_not_active  = 2
       internal_error     = 3
       OTHERS             = 4 ).

*HTTP Version
lo_http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).

*making REST client
CREATE OBJECT lo_rest_client
     EXPORTING
       io_http_client = lo_http_client.

*Fetching header DATA
select pkey value
  from ZETA_H_CONFIG
   into table it_HEADER_CONFIG
    where api = 'FETCHDOCS'.

  WA_HEADER_CONFIG-name  = 'Authorization'.
  WA_HEADER_CONFIG-value = token.
  append wa_header_config to it_header_config.

*setting Header Data
CALL METHOD lo_rest_client->if_rest_client~set_request_headers
  EXPORTING
    it_header_fields = it_header_config.

*GET method
lo_rest_client->if_rest_resource~get( ).

** Collect response
lo_response = lo_rest_client->if_rest_client~get_response_entity( ).
status = lv_status = lo_response->get_header_field( '~status_code' ).
response =  lo_response->GET_STRING_DATA( ).

*deserialize JSON TO ABAP .
CALL METHOD zeta_api_call=>deserialize_to_abap
  EXPORTING
    body   = response
  IMPORTING
    data   = resp_data.

       ASSIGN resp_data->* to <data>.

ASSIGN COMPONENT 'RESULT' OF STRUCTURE <data> TO <results>.

break-point.

   ASSIGN <results>->* to <table>.
clear <data>.
clear <results>.

loop at <table> assigning <structure>.

    ASSIGN <structure>->* to <data>.

 ASSIGN COMPONENT `DOCUMENTTYPEVERSIONS` OF STRUCTURE <data> TO <DOC_VER>.

 ASSIGN COMPONENT `id` OF STRUCTURE <data> TO <field>.
       assign <field>->* to <fieldvalue>.
        wa_docs-id = <fieldvalue>.
       unassign <fieldvalue>.

 ASSIGN COMPONENT `name` OF STRUCTURE <data> TO <field>.
        assign <field>->* to <fieldvalue>.
        wa_docs-name  = <fieldvalue>.
       unassign <fieldvalue>.

 ASSIGN COMPONENT `description` OF STRUCTURE <data> TO <field>.
        assign <field>->* to <fieldvalue>.
       wa_docs-description  = <fieldvalue>.
       unassign <fieldvalue>.
       unassign <field>.

 ASSIGN <DOC_VER>->* to <DOC_VER_T>.

     loop at <DOC_VER_T> assigning <results_ver>.
         ASSIGN <results_ver>->* to <results>.
        ASSIGN COMPONENT `id` OF STRUCTURE <results> TO <field>.

            assign <field>->* to <fieldvalue>.
           wa_docs-VER_ID  = <fieldvalue>.
           unassign <fieldvalue>.
           unassign <field>.

        ASSIGN COMPONENT `typename` OF STRUCTURE <results> TO <field>.
           assign <field>->* to <fieldvalue>.
           wa_docs-VER_TYPE  = <fieldvalue>.
           unassign <fieldvalue>.
           unassign <field>.

        ASSIGN COMPONENT `name` OF STRUCTURE <results> TO <field>.

           assign <field>->* to <fieldvalue>.
           wa_docs-VER_NAME  = <fieldvalue>.
           unassign <fieldvalue>.
           unassign <field>.

        ASSIGN COMPONENT `description` OF STRUCTURE <results> TO <field>.

           assign <field>->* to <fieldvalue>.
           wa_docs-VER_DESC  = <fieldvalue>.
           unassign <fieldvalue>.
           unassign <field>.

        ASSIGN COMPONENT `versionNumber` OF STRUCTURE <results> TO <field>.

            assign <field>->* to <fieldvalue>.
           wa_docs-VER_NUMBER   = <fieldvalue>.
           unassign <fieldvalue>.
           unassign <field>.

append wa_docs to it_docs.

     endloop.

endloop.

insert ZETA_DOC_TYPE_1 from table it_docs.
commit work.

  endmethod.

  method GET_SUBMIT_STATUS.
    data: lv_url type string,
          lv_data type ZETA_BILL_STATUS.
    data: validation_steps type ZSVALIDATIONSTEPS.
    clear: lo_http_client,lo_rest_client,lo_response,lo_request, lv_url,body.

    concatenate 'https://api.preprod.invoicing.eta.gov.eg/api/v1.0/documents/' UUID '/details' into lv_url.

*making HTTP client instance
cl_http_client=>create_by_url(
     EXPORTING
       url                = lv_url
     IMPORTING
       client             = lo_http_client
     EXCEPTIONS
       argument_not_found = 1
       plugin_not_active  = 2
       internal_error     = 3
       OTHERS             = 4 ).

*making REST client
CREATE OBJECT lo_rest_client
     EXPORTING
       io_http_client = lo_http_client.

   lo_http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).

*creating request instance
lo_request = lo_rest_client->if_rest_client~create_request_entity( ).

select pkey value
  from ZETA_H_CONFIG
   into table it_HEADER_CONFIG
    where api = 'SUBMISSION'.

  WA_HEADER_CONFIG-name  = 'Authorization'.
  WA_HEADER_CONFIG-value = token.
  append wa_header_config to it_header_config.

*SET header Data.
CALL METHOD lo_request->set_header_fields
  EXPORTING
   IT_HEADER_FIELDS = it_header_config.

*Get method
lo_rest_client->if_rest_resource~get( ).

** Collect response
lo_response = lo_rest_client->if_rest_client~get_response_entity( ).
status = lv_status = lo_response->get_header_field( '~status_code' ).
response =  lo_response->GET_STRING_DATA( ).

clear resp_data.
CALL METHOD zeta_api_call=>deserialize_to_abap
  EXPORTING
    body   = response
  IMPORTING
    data   = lv_data .

bill_status = lv_data-VALIDATIONRESULTS-STATUS.

  if bill_status = 'Invalid'.
     loop at lv_data-VALIDATIONRESULTS-validationSteps into validation_steps where status = 'Invalid'.
       append lines of validation_steps-error-INNERERROR to ERROR_MESSAGES.
     endloop.
  endif.

  endmethod.

  method MOCK_DATA.
**
**data : wa_issuer_data type ZST_ETA_ISSUER_RECEIVER_DATA.
**
**data : wa_receiver_data type ZST_ETA_ISSUER_RECEIVER_DATA.
**
**data: wa_payment_data type ZST_ETA_PAYMENT_DATA.
**
**data: wa_delivery_data type ZST_ETA_DELIVERY_DATA.
**
**data: wa_invoices_data type ZST_ETA_INVOICELINES_DATA,
**      it_invoices_data type table of ZST_ETA_INVOICELINES_DATA,
**      wa_unitValue_data type ZST_ETA_INVOICELINES_UNIT_DATA,
**      wa_discount_data  type ZST_ETA_INVOICELINES_DISC_DATA,
**      wa_taxItems_data  type ZST_ETA_TAX_ITEMS_DATA,
**      it_taxItems_data  type ZT_ETA_TAX_ITEMS_DATA.
**      it_taxItems_data  type table of ZST_ETA_TAX_ITEMS_DATA.
**
**data: wa_taxTotal_data type ZsT_ETA_TAX_TOTALS_DATA,
**      it_taxTotal_data type  ZsT_ETA_TAX_TOTALS_DATA.
**      it_taxTotal_data type table of ZsT_ETA_TAX_TOTALS_DATA.
**
**data: wa_Signatures_data type ZST_ETA_SIGNATURE_DATA,
**      it_Signatures_data type table of ZST_ETA_SIGNATURE_DATA.
**
**data: ST_DOC type ZST_ETA_DOCUMENT,
**      IT_DoC type table of ZST_ETA_DOCUMENT.
**
**ISSUER Data
***************************************************************
**wa_issuer_data-address-BRANCH_I_D = '0'.
**wa_issuer_data-address-COUNTRY = 'EG'.
**wa_issuer_data-address-GOVERNATE = 'CAIRO'.
**wa_issuer_data-address-REGIOn_city =  'NASR CITY'.
**wa_issuer_data-address-STREET = '580 Clementina Key'.
**wa_issuer_data-address-BUILDING_number = 'Bldg. 0'.
**wa_issuer_data-address-POSTal_CODE = '68030'.
**wa_issuer_data-address-FLOOR = '1'.
**wa_issuer_data-address-ROOM = '123'.
**wa_issuer_data-address-LANDMARK = '7660 Melody Trail'.
**wa_issuer_data-address-ADDITIONAL_INFORMATION = 'Beside Townhall'.
**wa_issuer_data-type = 'B'.
**wa_issuer_data-id = '100324932'.
**wa_issuer_data-NAME = 'شركة دريم'.
***************************************************************
**
**RECEIVER Data
***************************************************************
**wa_receiver_data-address-COUNTRY = 'EG'.
**wa_receiver_data-address-GOVERNATE = 'Egypt'.
**wa_receiver_data-address-REGIOn_city =  'Mufazat al Ismlyah'.
**wa_receiver_data-address-STREET = '580 Clementina Key'.
**wa_receiver_data-address-BUILDING_number = 'Bldg. 0'.
**wa_receiver_data-address-POSTal_CODE = '68030'.
**wa_receiver_data-address-FLOOR = '1'.
**wa_receiver_data-address-ROOM = '123'.
**wa_receiver_data-address-LANDMARK = '7660 Melody Trail'.
**wa_receiver_data-address-ADDITIONAL_INFORMATION = 'Beside Townhall'.
**wa_receiver_data-type = 'B'.
**wa_receiver_data-id = '313717919'.
**wa_receiver_data-NAME = 'A S Receiver'.
***************************************************************
**
***Payment Data
****************************************************************
**wa_payment_data-BANK_NAME = 'SomeValue'.
**wa_payment_data-BANK_ADDRESS = 'SomeValue'.
**wa_payment_data-BANK_ACCOUNT_NO = 'SomeValue'.
**wa_payment_data-BANK_ACCOUNT_I_B_A_N = ''.
**wa_payment_data-SWIFT_CODE = ''.
**wa_payment_data-TERMS = 'SomeValue'.
****************************************************************
**
***Devlivery Data
****************************************************************
**wa_delivery_data-APPROACH = 'SomeValue'.
**wa_delivery_data-PACKAGING = 'SomeValue'.
**wa_delivery_data-DATE_VALIDITY = '2020-09-28T09:30:10Z'.
**wa_delivery_data-EXPORT_PORT = 'SomeValue'.
**wa_delivery_data-COUNTRY_OF_ORIGIN = 'LS'.
**wa_delivery_data-GROSS_WEIGHT = '10.59100'.
**wa_delivery_data-NET_WEIGHT = '20.58700'.
**wa_delivery_data-TERMS = 'SomeValue'.
****************************************************************
**
***TAX Data
****************************************************************
**wa_invoices_data-DESCRIPTION = 'Computer1'.
**wa_invoices_data-ITEM_TYPE = 'GPC'.
**wa_invoices_data-ITEM_CODE = '10003752'.
**wa_invoices_data-UNIT_TYPE = 'EA'.
**wa_invoices_data-QUANTITY = '7.00000'.
**wa_invoices_data-INTERNAL_CODE = 'IC0'.
**wa_invoices_data-SALES_TOTAL = '662.90000'.
**wa_invoices_data-TOTAL = '2220.08914'.
**wa_invoices_data-VALUE_DIFFERENCE = '7.00000'.
**wa_invoices_data-TOTAL_TAXABLE_FEES = '618.69212'.
**wa_invoices_data-NET_TOTAL = '649.64200'.
**wa_invoices_data-ITEMS_DISCOUNT = '5.00000'.
*************
**wa_taxItems_data-TAX_TYPE = 'T1'.
**wa_taxItems_data-AMOUNT = '204.67639'.
**wa_taxItems_data-SUB_TYPE = 'V001'.
**wa_taxItems_data-RATE = '14.00'.
***append wa_taxItems_data to it_taxItems_data.
***clear wa_taxItems_data.
**
***wa_taxItems_data-TAX_TYPE = 'T2'.
***wa_taxItems_data-AMOUNT = '156.64009'.
***wa_taxItems_data-SUB_TYPE = 'Tbl01'.
***wa_taxItems_data-RATE = '12'.
****append wa_taxItems_data to it_taxItems_data.
***clear wa_taxItems_data.
**
**wa_invoices_data-TAXABLE_ITEMS = wa_taxItems_data.
*************
**wa_unitValue_data-CURRENCY_SOLD = 'USD'.
**wa_unitValue_data-AMOUNT_E_G_P = '94.70000'.
**wa_unitValue_data-AMOUNT_SOLD = '4.73500'.
**wa_unitValue_data-CURRENCY_EXCHANGE_RATE = '20.00000'.
**
**wa_invoices_data-UNIT_VALUE = wa_unitValue_data.
*************
**wa_discount_data-RATE = '2'.
**wa_discount_data-AMOUNT = '13.25800'.
**
**wa_invoices_data-DISCOUNT = wa_discount_data.
****************************************************************
**append wa_invoices_data to it_invoices_data.
****************************************************************
**
***TAX Totals
****************************************************************
**wa_taxTotal_data-TAX_TYPE = 'T1'.
**wa_taxTotal_data-AMOUNT = '1286.79112'.
***append wa_taxTotal_data to it_taxTotal_data.
***clear wa_taxTotal_data.
**
***wa_taxTotal_data-TAX_TYPE = 'T2'.
***wa_taxTotal_data-AMOUNT = '984.78912'.
***append wa_taxTotal_data to it_taxTotal_data.
***clear wa_taxTotal_data.
****************************************************************
**
***Signature
****************************************************************
**wa_Signatures_data-SIGNATURE_TYPE = 'I'.
**wa_Signatures_data-VALUE = 'No Signature'.
**append wa_Signatures_data to it_Signatures_data.
****************************************************************
**
***Fill Document
****************************************************************
**st_doc-issuer   = wa_issuer_DATA.
**st_doc-receiver = wa_receiver_data .
**st_doc-DOCUMENT_TYPE = 'I' .
**st_doc-DOCUMENT_TYPE_VERSION = '0.9' .
**st_doc-DATE_TIME_ISSUED = '2021-02-01T02:04:45Z' .
**st_doc-TAXPAYER_ACTIVITY_CODE = '4620' .
**st_doc-INTERNAL_I_D = 'A100001' .
**st_doc-PURCHASE_ORDER_REFERENCE = 'A00002' .
**st_doc-PURCHASE_ORDER_DESCRIPTION = 'purchase Order description' .
**st_doc-SALES_ORDER_REFERENCE = '1231' .
**st_doc-SALES_ORDER_DESCRIPTION = 'sales Order description' .
**st_doc-PROFORMA_INVOICE_NUMBER = 'SomeValue' .
**st_doc-payment = wa_payment_data.
**st_doc-delivery = wa_delivery_data.
**st_doc-INVOICE_LINES = it_invoices_data.
**st_doc-TAX_TOTALS = it_taxTotal_data.
**
**st_doc-TOTAL_DISCOUNT_AMOUNT = '214.41458'.
**st_doc-TOTAL_SALES_AMOUNT = '4419.56300'.
**st_doc-NET_AMOUNT = '4205.14842'.
**st_doc-TOTAL_AMOUNT = '14082.88542'.
**
**st_doc-EXTRA_DISCOUNT_AMOUNT = '5.00000'.
**st_doc-TOTAL_ITEMS_DISCOUNT_AMOUNT = '25.00000'.
**st_doc-SIGNATURES = it_Signatures_data.
**
**append st_doc to it_doc.
**
**data-documents = it_doc.
**
  endmethod.

  method SERIALIZE_TO_JSON.

JSON_DATA = /ui2/cl_json=>serialize( data = data compress = abap_false
                                   pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                                   TS_AS_ISO8601 = abap_true ).

  endmethod.

  method TOKEN_EXTRACTION.

  FIELD-SYMBOLS:
  <data>        TYPE data,
  <results>     TYPE any,
  <structure>   TYPE any,
  <table>       TYPE any table,
  <field>       TYPE data,
  <field_value> TYPE data.

data: resp type xstring,
      respc type string.

*Fetch Static Data of username, password and URL
SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO USERNAME
      WHERE PKEY = 'USERNAME'.

SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO PASSWORD
      WHERE PKEY = 'PASSWORD'.

SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO LV_URL
      WHERE PKEY = 'TOKEN_URL'.

SELECT SINGLE VALUE
    FROM ZETA_PARAMS
     INTO LV_BODY
      WHERE PKEY = 'TOKEN_BODY'.

*making HTTP client instance
cl_http_client=>create_by_url(
     EXPORTING
       url                = lv_url
     IMPORTING
       client             = lo_http_client
     EXCEPTIONS
       argument_not_found = 1
       plugin_not_active  = 2
       internal_error     = 3
       OTHERS             = 4 ).

*Authentication Parameters
   lo_http_client->propertytype_logon_popup = lo_http_client->co_disabled.
   CALL METHOD lo_http_client->authenticate
     EXPORTING
       username =  username
       password =  password.

*making REST client
CREATE OBJECT lo_rest_client
     EXPORTING
       io_http_client = lo_http_client.

   lo_http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).

*creating request instance
lo_request = lo_rest_client->if_rest_client~create_request_entity( ).

*add header Data.
CALL METHOD lo_request->set_header_field
  EXPORTING
    iv_name  = 'Content-Type'
    iv_value = if_rest_media_type=>GC_APPL_WWW_FORM_URL_ENCODED .

*Passing data to request body
lo_request->set_string_data( lv_body ).

*Post method
lo_rest_client->if_rest_resource~post( lo_request ).

** Collect response
lo_response = lo_rest_client->if_rest_client~get_response_entity( ).
status = lv_status = lo_response->get_header_field( '~status_code' ).
Body =  lo_response->GET_STRING_DATA( ).

*Deserialize JSON Response data to ABAP Data
call method ZETA_API_CALL=>DESERIALIZE_TO_ABAP
  exporting
     body = body
  importing
    data = resp_data.

if resp_data is bound.

    ASSIGN resp_data->* TO <data>.

      ASSIGN COMPONENT `access_token` OF STRUCTURE <data> TO <field>.

        if <field> is assigned.
              resp_data = <field>.
              ASSIGN resp_data->* TO <field_value>.
              lv_token = <field_value>.
        endif.

endif.

concatenate 'Bearer' lv_token into token SEPARATED BY space.

  endmethod.
ENDCLASS.