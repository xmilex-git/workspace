rep('''  if (client_credential->login_name.empty ())
    {
      if (getuserid (boot_Client_id_buffer, L_cuserid) != (char *) NULL)
	{
	  client_credential->login_name = boot_Client_id_buffer;
	}
      else
	{
	  client_credential->login_name = boot_Client_id_unknown_string;
	}
    }''','''  if (client_credential->login_name.empty ())
    {
#if defined (SERVER_MODE)
      /* the server's login name, read once by its boot (boot_initialize_client_modules) */
      client_credential->login_name = boot_Client_id_buffer;
#else
      if (getuserid (boot_Client_id_buffer, L_cuserid) != (char *) NULL)
	{
	  client_credential->login_name = boot_Client_id_buffer;
	}
      else
	{
	  client_credential->login_name = boot_Client_id_unknown_string;
	}
#endif
    }''')
rep('''char *
boot_get_ip (void)
{
  struct hostent *hp = NULL;
  if (boot_Host_name[0] == '\\0')
    {
      boot_get_host_name ();
    }

  if ((hp = gethostbyname_uhost (boot_Host_name)) != NULL)
    {
      char *ip = inet_ntoa (*(struct in_addr *) *hp->h_addr_list);
      memcpy (boot_Ip_address, ip, 15);
    }

  return boot_Ip_address;
}''','''static void
boot_initialize_ip (void)
{
  struct hostent *hp = NULL;
  if (boot_Host_name[0] == '\\0')
    {
      boot_get_host_name ();
    }

  if ((hp = gethostbyname_uhost (boot_Host_name)) != NULL)
    {
      char *ip = inet_ntoa (*(struct in_addr *) *hp->h_addr_list);
      memcpy (boot_Ip_address, ip, 15);
    }
}

char *
boot_get_ip (void)
{
#if !defined (SERVER_MODE)
  /* the folded server resolved it once at its boot (boot_initialize_client_modules) */
  boot_initialize_ip ();
#endif

  return boot_Ip_address;
}''')
rep('''static int
boot_register_and_init_client (BOOT_CLIENT_CREDENTIAL * client_credential, bool is_sub_client)
{''','''/* does this boot initialize the client modules the process shares?  A sub-client shares the main client's; every
 * in-process session of the folded server shares the server boot's (boot_initialize_client_modules) */
#if defined (SERVER_MODE)
#define BOOT_INIT_SHARED_MODULES(is_sub_client) false
#else
#define BOOT_INIT_SHARED_MODULES(is_sub_client) (!(is_sub_client))
#endif

static int
boot_register_and_init_client (BOOT_CLIENT_CREDENTIAL * client_credential, bool is_sub_client)
{''')
R=('boot_register_and_init_client (BOOT_CLIENT_CREDENTIAL * client_credential, bool is_sub_client)\n{','\n}\n')
rep('''  if (!is_sub_client)
    {
      /* this must be done before the register_client because recovery steps may need domains. */''','''  if (BOOT_INIT_SHARED_MODULES (is_sub_client))
    {
      /* this must be done before the register_client because recovery steps may need domains. */''',region=R)
rep('''      if (sysprm_init_intl_param () != NO_ERROR)''','''      if (BOOT_INIT_SHARED_MODULES (is_sub_client) && sysprm_init_intl_param () != NO_ERROR)''',region=R)
for tail in ['''      oid_set_root (&boot_Server_credential.root_class_oid);''','''      error_code = boot_client_find_and_cache_class_oids ();''','''      /* TODO: how about to call es_init() only for normal client? */''','''      error_code = showstmt_metadata_init ();''']:
    rep('''  if (!is_sub_client)
    {
'''+tail,'''  if (BOOT_INIT_SHARED_MODULES (is_sub_client))
    {
'''+tail,region=R)
rep('''  sm_init (&boot_Server_credential.root_class_oid, &boot_Server_credential.root_class_hfid, is_sub_client);''','''  sm_init (&boot_Server_credential.root_class_oid, &boot_Server_credential.root_class_hfid,
	   !BOOT_INIT_SHARED_MODULES (is_sub_client));''',region=R)
R2=('\nboot_restart_client (BOOT_CLIENT_CREDENTIAL * client_credential)\n{','\n}\n')
rep('''  pr_Enable_string_compression = prm_get_bool_value (PRM_ID_ENABLE_STRING_COMPRESSION);
''','''#if !defined (SERVER_MODE)
  /* the folded server's boot set it */
  pr_Enable_string_compression = prm_get_bool_value (PRM_ID_ENABLE_STRING_COMPRESSION);
#endif
''',region=R2)
rep('''   * loader fails, methods will fail when they are invoked
   */
#if !defined(WINDOWS)
''','''   * loader fails, methods will fail when they are invoked; the folded server's boot initialized its one loader
   */
#if !defined(WINDOWS) && !defined (SERVER_MODE)
''',region=R2)
rep('''  dl_initialized = true;
#endif /* !WINDOWS */
''','''  dl_initialized = true;
#endif /* !WINDOWS && !SERVER_MODE */
''',region=R2)
