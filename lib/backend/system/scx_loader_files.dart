/// cargo 安装路径需要写入的 scx-loader 系统集成文件。
///
/// 内容与上游 scx-loader 1.1.3 的 `services/`、`configs/` 目录一致：
/// systemd 单元、D-Bus 激活/策略/接口文件、polkit 策略与示例配置。
/// apt 安装路径（scx-loader 软件包）会提供同样的文件。
class ScxLoaderSystemFile {
  const ScxLoaderSystemFile(this.path, this.content);

  /// 目标绝对路径（特权辅助进程的写入白名单与本清单保持一致）。
  final String path;

  /// 文件内容。
  final String content;
}

/// 需要写入系统的 scx-loader 集成文件清单。
const scxLoaderSystemFiles = <ScxLoaderSystemFile>[
  ScxLoaderSystemFile(
    '/usr/lib/systemd/system/scx_loader.service',
    _scxLoaderUnit,
  ),
  ScxLoaderSystemFile(
    '/usr/share/dbus-1/system-services/org.scx.Loader.service',
    _dbusActivation,
  ),
  ScxLoaderSystemFile(
    '/usr/share/dbus-1/system.d/org.scx.Loader.conf',
    _dbusPolicy,
  ),
  ScxLoaderSystemFile(
    '/usr/share/dbus-1/interfaces/org.scx.Loader.xml',
    _dbusInterface,
  ),
  ScxLoaderSystemFile(
    '/usr/share/polkit-1/actions/org.scx.Loader.policy',
    _polkitPolicy,
  ),
  ScxLoaderSystemFile('/usr/share/scx_loader/config.toml', _exampleConfig),
];

const _scxLoaderUnit = r'''[Unit]
Description=DBUS on-demand loader of sched-ext schedulers

[Service]
Type=dbus
BusName=org.scx.Loader
ExecStart=/usr/bin/scx_loader
KillSignal=SIGINT
ProtectSystem=full
PrivateTmp=disconnected
PrivateMounts=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
LockPersonality=true
RestrictRealtime=true
ProtectClock=true
MemoryDenyWriteExecute=true
RestrictAddressFamilies=AF_UNIX
SocketBindDeny=ipv4:tcp
SocketBindDeny=ipv4:udp
SocketBindDeny=ipv6:tcp
SocketBindDeny=ipv6:udp
CapabilityBoundingSet=~CAP_BLOCK_SUSPEND CAP_CHOWN CAP_MKNOD CAP_NET_RAW CAP_SYS_BOOT CAP_SYS_CHROOT CAP_SYS_MODULE CAP_SYS_PACCT CAP_SYS_PTRACE CAP_SYS_TIME CAP_SYSLOG CAP_WAKE_ALARM
SystemCallFilter=~@aio:EPERM @chown:EPERM @clock:EPERM @cpu-emulation:EPERM @debug:EPERM @keyring:EPERM @module:EPERM @mount:EPERM @obsolete:EPERM @pkey:EPERM @raw-io:EPERM @reboot:EPERM @setuid:EPERM @swap:EPERM @sync:EPERM @timer:EPERM
SystemCallFilter=perf_event_open

[Install]
WantedBy=multi-user.target
''';

const _dbusActivation = r'''[D-BUS Service]
Name=org.scx.Loader
Exec=/usr/bin/scx_loader
User=root
SystemdService=scx_loader.service
''';

const _dbusPolicy = r'''<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>

    <policy user="root">
        <allow own="org.scx.Loader"/>

        <allow send_destination="org.scx.Loader"/>
        <allow receive_sender="org.scx.Loader"/>
    </policy>

    <policy context="default">
        <deny send_destination="org.scx.Loader"/>

        <!-- Completely open to anyone: org.freedesktop.DBus.* interfaces -->

        <allow send_destination="org.scx.Loader"
               send_interface="org.freedesktop.DBus.Introspectable"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.freedesktop.DBus.Peer"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.freedesktop.DBus.Properties"
               send_member="Get"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.freedesktop.DBus.Properties"
               send_member="GetAll"/>

        <!-- Managed via polkit: org.scx.loader.manage-schedulers action id -->

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="StartScheduler"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="StartSchedulerWithArgs"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="SwitchScheduler"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="SwitchSchedulerWithArgs"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="StopScheduler"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="RestartScheduler"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="RestoreDefault"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="SchedulerModes"/>

        <allow send_destination="org.scx.Loader"
               send_interface="org.scx.Loader"
               send_member="SchedulerModeArgs"/>

        <allow receive_sender="org.scx.Loader"/>
    </policy>

</busconfig>
''';

const _dbusInterface = r'''<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <!--
      org.scx.Loader:
      @short_description: Scheduler Loader Service

      The Scheduler Loader service provides an interface for managing schedulers
      that can be used with sched-ext. It allows starting, stopping, switching and querying
      the status of supported schedulers.
  -->
  <interface name="org.scx.Loader">

    <!--
        CurrentScheduler:

        The name of the currently running scheduler. If no scheduler is active,
        this property will be set to "unknown".
    -->
    <property name="CurrentScheduler" type="s" access="read"/>

    <!--
        SchedulerMode:
        @sched_mode: 0 = Auto, 1 = Gaming, 2 = PowerSave, 3 = LowLatency, 4 = Server

        The currently active scheduler mode.  Scheduler modes allow you to
        apply pre-defined configurations to a scheduler that are
        optimized for different use cases. If no scheduler is active,
        this property will be set to 0 (Auto).
    -->
    <property name="SchedulerMode" type="u" access="read"/>

    <!--
        CurrentSchedulerArgs:

        The arguments used for the currently running scheduler. If no scheduler
        is active or the scheduler was started with a predefined mode (not custom
        arguments), this property will return an empty array.
    -->
    <property name="CurrentSchedulerArgs" type="as" access="read"/>
    <!--
        SupportedSchedulers:

        A list of the schedulers currently supported by the Scheduler Loader.
        The names of the supported schedulers will be listed as strings in
        this array.
    -->
    <property name="SupportedSchedulers" type="as" access="read"/>

    <!--
        DefaultScheduler:

        The name of the default scheduler configured in the config file.
        If no default scheduler is configured, this property will be set
        to "unknown".
    -->
    <property name="DefaultScheduler" type="s" access="read"/>

    <!--
        DefaultMode:
        @sched_mode: 0 = Auto, 1 = Gaming, 2 = PowerSave, 3 = LowLatency, 4 = Server

        The default scheduler mode configured in the config file.
        Defaults to 0 (Auto) if not explicitly configured.
    -->
    <property name="DefaultMode" type="u" access="read"/>

    <!--
        SchedulerModes:

        Returns the scheduler modes that are meaningfully configured for the
        given scheduler, i.e. the modes that resolve to a non-empty argument
        list. Auto (0) is always included, since it represents the
        scheduler's own defaults and is valid even without explicit
        arguments.

        Clients can use this to discover ahead of time which modes will
        have mode-specific arguments applied, rather than finding out only
        after starting/switching that no such arguments are configured.

        @scx_name: The name of the scheduler to query (e.g., "scx_rusty").
        @sched_modes: An array of scheduler modes (see the SchedulerMode
                    property for the meaning of each value) that are
                    meaningfully configured for this scheduler.
    -->
    <method name="SchedulerModes">
      <arg name="scx_name" type="s" direction="in"/>
      <arg name="sched_modes" type="au" direction="out"/>
    </method>

    <!--
        SchedulerModeArgs:

        Returns the resolved arguments for every mode of the given
        scheduler, in a stable order. A mode with no configured arguments
        comes back with an empty array, meaning it would just run the
        scheduler with its own built-in defaults for that mode.

        Unlike SchedulerModes, this returns every mode together with its
        actual arguments, so clients can show the exact configuration
        instead of just which modes are configured.

        @scx_name: The name of the scheduler to query (e.g., "scx_rusty").
        @mode_args: An array of (mode, arguments) pairs, one per scheduler
                    mode (see the SchedulerMode property for the meaning of
                    each mode value).
    -->
    <method name="SchedulerModeArgs">
      <arg name="scx_name" type="s" direction="in"/>
      <arg name="mode_args" type="a(uas)" direction="out"/>
    </method>

    <!--
        StartScheduler:

        Starts the specified scheduler with the given mode.

        @scx_name: The name of the scheduler to start (e.g., "scx_rusty").
        @sched_mode: The scheduler mode (profile) as an unsigned integer.
                   See the SchedulerMode property for details.
    -->
    <method name="StartScheduler">
      <arg name="scx_name" type="s" direction="in"/>
      <arg name="sched_mode" type="u" direction="in"/>
    </method>

    <!--
        StartSchedulerWithArgs:

        Starts the specified scheduler with the provided arguments.

        @scx_name: The name of the scheduler to start (e.g., "scx_bpfland").
        @scx_args: An array of strings representing the CLI arguments to pass
                    to the scheduler.
    -->
    <method name="StartSchedulerWithArgs">
      <arg name="scx_name" type="s" direction="in"/>
      <arg name="scx_args" type="as" direction="in"/>
    </method>

    <!--
        SwitchScheduler:

        Switches to the specified scheduler with the given mode. This method
        will stop the currently running scheduler (if any) and then start the
        new scheduler.

        @scx_name: The name of the scheduler to switch to (e.g., "scx_rusty").
        @sched_mode: The scheduler mode (profile) as an unsigned integer.
                   See the SchedulerMode property for details.
    -->
    <method name="SwitchScheduler">
      <arg name="scx_name" type="s" direction="in"/>
      <arg name="sched_mode" type="u" direction="in"/>
    </method>

    <!--
        SwitchSchedulerWithArgs:

        Switches to the specified scheduler with the provided arguments. This
        method will stop the currently running scheduler (if any) and then
        start the new scheduler with the given arguments.

        @scx_name: The name of the scheduler to switch to (e.g., "scx_bpfland").
        @scx_args: An array of strings representing the CLI arguments to pass
                    to the scheduler.
    -->
    <method name="SwitchSchedulerWithArgs">
      <arg name="scx_name" type="s" direction="in"/>
      <arg name="scx_args" type="as" direction="in"/>
    </method>

    <!--
        StopScheduler:

        Stops the currently running scheduler.
    -->
    <method name="StopScheduler">
    </method>

    <!--
        RestartScheduler:

        Restarts the currently running scheduler with its original configuration.
        This method will stop the currently running scheduler and then restart 
        it with the same scheduler and arguments/mode that were used originally.
        Returns an error if no scheduler is currently running.
    -->
    <method name="RestartScheduler">
    </method>

    <!--
        RestoreDefault:

        Switches to the default scheduler with the default mode as configured
        in the config file. This method will stop the currently running
        scheduler (if any) and then start the default scheduler.
        Returns an error if no default scheduler is configured.
    -->
    <method name="RestoreDefault">
    </method>
  </interface>
</node>
''';

const _polkitPolicy = r'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">

<policyconfig>

  <vendor>ScxLoader</vendor>
  <vendor_url>https://github.com/sched-ext/scx-loader</vendor_url>

  <action id="org.scx.loader.manage-schedulers">
    <description>Manage sched-ext schedulers</description>
    <message>Authentication is required to start, stop, or switch sched-ext schedulers.</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
  </action>

</policyconfig>
''';

const _exampleConfig = r'''# This field specifies the scheduler that will be started automatically when scx_loader starts (e.g., on boot).
#default_sched = "scx_cosmos"

# This field specifies the mode which will be used when scx_loader starts (e.g., on boot).
#default_mode = "Auto"

# This "structure" allows configuring flags for each scheduler mode of particular scx scheduler
#[scheds.'scheduler']
#auto_mode = []
#gaming_mode = []
#lowlatency_mode = []
#powersave_mode = []
#server_mode = []
''';
