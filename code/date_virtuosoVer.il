/***********************************************************
 * Return formatted current time string: YYYYMMDD_HHMMSS
 ***********************************************************/
procedure(getReadableTime()
  let((tokens monthStr day time year hms hour min sec monthNum)
    tokens = parseString(getCurrentTime())
    monthStr = nth(0 tokens)
    day     = nth(1 tokens)
    time    = nth(2 tokens)
    year    = nth(3 tokens)
    hms     = parseString(time ":")
    hour    = nth(0 hms)
    min     = nth(1 hms)
    sec     = nth(2 hms)
    monthNum = case(monthStr
      ("Jan" "01")
      ("Feb" "02")
      ("Mar" "03")
      ("Apr" "04")
      ("May" "05")
      ("Jun" "06")
      ("Jul" "07")
      ("Aug" "08")
      ("Sep" "09")
      ("Oct" "10")
      ("Nov" "11")
      ("Dec" "12")
    )
    day = sprintf(nil "%02d" atoi(day))
    sprintf(nil "%s%s%s_%s%s%s" year monthNum day hour min sec)
  )
)

/***********************************************************
 * Generate or reuse date + Virtuoso version string
 ***********************************************************/
procedure(date_virtuosoVer(@optional (prefix ""))
  let((filePath port ver date_virtuosoVer)
    filePath = strcat(prefix "date_virtuosoVer.txt")
    if(isFile(filePath) then
      ; read existing content
      port = infile(filePath)
      gets(date_virtuosoVer port)
      close(port)
      ; remove newline
      date_virtuosoVer = substring(date_virtuosoVer 1 strlen(date_virtuosoVer)-1)
    else
      ; remove "sub-version"
      rexCompile("sub-version")
      ver = rexReplace(getVersion(t) "" 1)
      ; remove all spaces
      rexCompile(" ")
      ver = rexReplace(ver "" 0)
      ; create readable timestamp + version
      date_virtuosoVer = strcat(
        getReadableTime()
        "_"
        ver
      )
      ; save to file (cache)
      port = outfile(filePath)
      fprintf(port "%s\n" date_virtuosoVer)
      close(port)
    )
    date_virtuosoVer
  )
)
