procedure(Validate(ddid expectedState expectedVersion)
  prog((speclist result)
    result = t
    speclist = gdmCreateSpecList()
    gdmAddSpecToSpecList(gdmCreateSpecFromDDID(ddid) speclist)
    rexCompile("(\\.cdslck.*)|(\\.oacache.*)|(\\.tmp\\.[a-z])")
    foreach(spec gdmstatus(speclist 6)
      tokens = parseString(car(spec))
      unless(or(
          rexMatchp("\\.cdslck.*"  car(tokens))
          rexMatchp("\\.oacache.*" car(tokens))
          rexMatchp("\\.tmp\\.[a-z]" car(tokens))
          rexMatchp("data.dm\\.*" car(tokens)))
        if(strcmp(cadr(tokens) expectedState) != 0 then
          printf("ERROR: %s expected %s but got %s\n"
            car(tokens) expectedState cadr(tokens))
          result = nil
        )
      )
    )
    gdmResetSpecList(speclist)
    foreach(spec gdmstatus(speclist 10)
      tokens = parseString(car(spec))
      unless(or(
          rexMatchp("\\.cdslck.*"  car(tokens))
          rexMatchp("\\.oacache.*" car(tokens))
          rexMatchp("\\.tmp\\.[a-z]" car(tokens))
          rexMatchp("data.dm\\.*" car(tokens)))
        if(strcmp(cadr(tokens) expectedVersion) != 0 then
          printf("ERROR: %s expected version %s but got %s\n"
            car(tokens) expectedVersion cadr(tokens))
          result = nil
        )
      )
    )
    return(result)
  )
)
