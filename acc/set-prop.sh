set_prop() {

  local daemonWasUp=true restartDaemon=false

  daemon_ctrl > /dev/null || daemonWasUp=false

  (case ${1-} in

    # set multiple properties
    *=*)
      . $defaultConfig
      . $config
      export "$@"
    ;;

    # reset config
    r|--reset)
      cp $defaultConfig $config
      print_config_reset
      ! $daemonWasUp || /sbin/accd
      return 0
    ;;

    # print default config
    d|--print-default)
      . $defaultConfig
      . $modPath/print-config.sh | grep -E "${2:-.}"
      return 0
    ;;

    # print current config
    p|--print)
      . $modPath/print-config.sh | grep -E "${2:-.}"
      return 0
    ;;

    # set switch
    s|--charging*witch)
        IFS=$'\n'
        PS3="$(echo; print_choice_prompt)"
        print_known_switch
        echo
        eval 'select chargingSwitch in $(print_auto) $(cat $TMPDIR/charging-switches) $(print_exit); do
          [ ${chargingSwitch:-x} != $(print_exit) ] || exit 0
          [ ${chargingSwitch:-x} == $(print_auto) ] && charging_switch= || :
          eval "chargingSwitch=($chargingSwitch)"
          break
        done'
        unset IFS
    ;;

    # print switches
    s:|--charging*witch:)
      cat $TMPDIR/charging-switches
      return 0
    ;;


    # set charging current
    c|--current)

      # check support
      if ! grep -q ::v $TMPDIR/ch-curr-ctrl-files; then
        if not_charging; then
          (while not_charging; do
            clear
            echo
            print_read_curr
            sleep 1
            set +x
          done)
          echo
          echo
          . $modPath/read-ch-curr-ctrl-files-p2.sh
          if ! grep -q ::v $TMPDIR/ch-curr-ctrl-files; then
            print_unsupported
            return 1
          fi
        else
          . $modPath/read-ch-curr-ctrl-files-p2.sh
          if ! grep -q ::v $TMPDIR/ch-curr-ctrl-files; then
            print_unsupported
            return 1
          fi
        fi
      fi

      if [ -n "${2-}" ]; then

        # restore
        if [ $2 == - ]; then
          daemon_ctrl stop skipab > /dev/null \
            || { . $modPath/apply-on-plug.sh; apply_on_plug default; }
          restartDaemon=true
          max_charging_current=
          print_curr_restored

        else

          apply_current() {
            eval "maxChargingCurrent=($1 $(sed "s|::v|::$1|" $TMPDIR/ch-curr-ctrl-files))" \
              && { . $modPath/apply-on-plug.sh; apply_on_plug; } \
              && { noEcho=true; print_curr_set $1; } || return 1
          }

          # [0-9999] milliamps range
          if [ $2 -ge 0 -a $2 -le 9999 ]; then
            apply_current $2 || return 1
          else
            echo "(!) [0-9999] ($(print_mA | sed 's/^ //')) $(print_only)"
            return 1
          fi
        fi

      else
        # print current value
        echo "${maxChargingCurrent[0]:-$(print_default)}$(! ${verbose:-true} || print_mA)"
        return 0
      fi
    ;;


    # set charging voltage
    v|--voltage)
      if [ -n "${2-}" ]; then

        # restore
        if [ $2 == - ]; then
          daemon_ctrl stop forceab> /dev/null \
            || { . $modPath/apply-on-boot.sh; apply_on_boot default force; }
          restartDaemon=true
          max_charging_voltage=
          print_volt_restored

        else

          apply_voltage() {
            [ ${2:-x} != --exit ] || { ! $daemonWasUp || daemon_ctrl stop; }
            eval "maxChargingVoltage=($1 $(sed "s|vvvv|$1|" $TMPDIR/ch-volt-ctrl-files) ${2-})" \
              && { . $modPath/apply-on-boot.sh; (apply_on_boot); } \
              && { noEcho=true; print_volt_set $1; } || return 1
          }

          # == [3700-4200] millivolts
          if [ $2 -ge 3700 -a $2 -le 4200 ]; then
            apply_voltage $2 ${2-} || return 1

          # < 3700 millivolts
          elif [ $2 -lt 3700 ]; then
            echo "(!) [3700-4200] ($(print_mV | sed 's/^ //')) $(print_only)"
            apply_voltage 3700 ${2-} || return 1

          # > 4200 millivolts
          elif [ $2 -gt 4200 ]; then
            echo "(!) [3700-4200] ($(print_mV | sed 's/^ //')) $(print_only)"
            apply_voltage 4200 ${2-} || return 1
          fi
        fi

      else
        # print current value
        echo "${maxChargingVoltage[0]:-$(print_default)}$(! ${verbose:-true} || print_mV)"
        return 0
      fi
    ;;


    # set language
    l|--lang)
        IFS=$'\n'
        PS3="$(echo; print_choice_prompt)"
        eval 'select _lang in $(echo "- English (en)" | grep -v $language; \
          (for file in $(ls -1 $modPath/translations/*/strings.sh); do \
            sed -n "'s/# /- /p'" $file | grep -v $language; \
          done); print_exit)
        do
          lang=${_lang#*\(}
          [ $lang != $(print_exit) ] || exit 0
          lang=${lang%\)*}
          break
        done'
        unset IFS
    ;;

    # print current config (full)
    *)
      . $modPath/print-config.sh
      return 0
    ;;

  esac

  # update config.txt
  . $modPath/write-config.sh
  ! $restartDaemon || { ! $daemonWasUp || /sbin/accd; })
}
