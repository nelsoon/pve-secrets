// Datacenter -> Secrets: first-time setup (shows the recovery keys once) and
// store status. SPDX-License-Identifier: AGPL-3.0-or-later

Ext.define('PVE.secrets.RecoveryKeys', {
    extend: 'Ext.window.Window',
    alias: 'widget.pveSecretsRecoveryKeys',

    title: gettext('Recovery keys'),
    modal: true,
    closable: false,
    width: 620,
    layout: { type: 'vbox', align: 'stretch' },
    bodyPadding: 10,

    keys: [],
    threshold: 3,

    initComponent: function() {
        let me = this;
        let text = me.keys.join('\n');
        me.items = [
            {
                xtype: 'component',
                html: Ext.String.format(gettext(
                    'Save these recovery keys now, somewhere outside this cluster (password ' +
                    'manager, printed copy). They are <b>not stored anywhere</b> and cannot ' +
                    'be shown again. Any {0} of the {1} keys are needed to regain admin ' +
                    'access if the admin token is lost.'), me.threshold, me.keys.length),
                margin: '0 0 10 0',
            },
            {
                xtype: 'textarea',
                value: text,
                readOnly: true,
                height: 130,
                fieldStyle: 'font-family: monospace;',
            },
            {
                xtype: 'checkbox',
                itemId: 'saved',
                boxLabel: gettext('I have saved the recovery keys'),
                listeners: {
                    change: (cb, v) => me.down('#close').setDisabled(!v),
                },
            },
        ];
        me.buttons = [
            {
                text: gettext('Download'),
                iconCls: 'fa fa-download',
                handler: function() {
                    let blob = new Blob(
                        ['pve-secrets recovery keys (' + new Date().toISOString() + ')\n' +
                         'threshold: ' + me.threshold + ' of ' + me.keys.length + '\n\n' +
                         text + '\n'], { type: 'text/plain' });
                    let a = document.createElement('a');
                    a.href = URL.createObjectURL(blob);
                    a.download = 'pve-secrets-recovery-keys.txt';
                    a.click();
                    URL.revokeObjectURL(a.href);
                },
            },
            {
                text: gettext('Copy'),
                iconCls: 'fa fa-clipboard',
                handler: () => navigator.clipboard?.writeText(text),
            },
            '->',
            {
                text: gettext('Close'),
                itemId: 'close',
                disabled: true,
                handler: function() {
                    me.keys = [];
                    me.down('textarea').setValue('');
                    me.destroy();
                },
            },
        ];
        me.callParent();
    },
});

Ext.define('PVE.secrets.Setup', {
    extend: 'Ext.window.Window',
    alias: 'widget.pveSecretsSetup',

    title: gettext('Set up secret store'),
    modal: true,
    width: 480,
    bodyPadding: 10,
    layout: 'fit',

    initComponent: function() {
        let me = this;
        me.items = [{
            xtype: 'form',
            border: false,
            defaults: { anchor: '100%', labelWidth: 140 },
            items: [
                {
                    xtype: 'component',
                    html: gettext('Starts OpenBao on every node of this cluster. Clients ' +
                        'use one address, held by a healthy node.'),
                    margin: '0 0 10 0',
                },
                {
                    xtype: 'proxmoxtextfield',
                    name: 'vip',
                    fieldLabel: gettext('Address (CIDR)'),
                    emptyText: '192.0.2.10/24',
                    vtype: 'IPCIDRAddress',
                    allowBlank: false,
                },
                {
                    xtype: 'proxmoxtextfield',
                    name: 'name',
                    fieldLabel: gettext('DNS name'),
                    emptyText: gettext('optional'),
                    vtype: 'DnsName',
                    skipEmptyText: true,
                },
                {
                    xtype: 'proxmoxtextfield',
                    name: 'interface',
                    fieldLabel: gettext('Interface'),
                    emptyText: 'vmbr0',
                    skipEmptyText: true,
                },
                {
                    xtype: 'proxmoxintegerfield',
                    name: 'vrid',
                    fieldLabel: gettext('VRRP router id'),
                    emptyText: '90',
                    minValue: 1,
                    maxValue: 255,
                    skipEmptyText: true,
                },
            ],
        }];
        me.buttons = [{
            text: gettext('Set up'),
            itemId: 'submit',
            handler: function() {
                let form = me.down('form').getForm();
                if (!form.isValid()) {
                    return;
                }
                let params = {};
                Ext.Object.each(form.getValues(), (k, v) => {
                    if (v !== '' && v !== null) {
                        params[k] = v;
                    }
                });
                me.setLoading(gettext('Setting up...'));
                Proxmox.Utils.API2Request({
                    url: '/cluster/secrets/init',
                    method: 'POST',
                    params: params,
                    timeout: 150 * 1000,
                    failure: function(response) {
                        me.setLoading(false);
                        Ext.Msg.alert(gettext('Error'), response.htmlStatus);
                    },
                    success: function(response) {
                        let d = response.result.data;
                        me.destroy();
                        Ext.create('PVE.secrets.RecoveryKeys', {
                            keys: d.recovery_keys,
                            threshold: d.threshold,
                            listeners: { destroy: () => me.onDone?.() },
                        }).show();
                    },
                });
            },
        }];
        me.callParent();
    },
});

Ext.define('PVE.secrets.BackupEdit', {
    extend: 'Proxmox.window.Edit',
    alias: 'widget.pveSecretsBackupEdit',

    subject: gettext('Backup'),
    url: '/api2/extjs/cluster/secrets/backup',
    method: 'PUT',
    width: 460,

    items: [
        {
            xtype: 'pveStorageSelector',
            name: 'storage',
            fieldLabel: gettext('Storage'),
            storageContent: 'backup',
            nodename: 'localhost',
            allowBlank: false,
        },
        {
            xtype: 'proxmoxintegerfield',
            name: 'interval',
            fieldLabel: gettext('Every (hours)'),
            minValue: 1,
            maxValue: 720,
            value: 24,
        },
        {
            xtype: 'proxmoxintegerfield',
            name: 'keep',
            fieldLabel: gettext('Keep'),
            minValue: 1,
            maxValue: 1000,
            value: 14,
        },
        {
            xtype: 'displayfield',
            userCls: 'pmx-hint',
            value: gettext('Snapshots are encrypted by the store. Restoring one on a rebuilt ' +
                'cluster needs the seal key (pve-secrets export-seal-key, as root) and 3 ' +
                'recovery keys: keep the seal key offline with the recovery keys.'),
        },
    ],
});

Ext.define('PVE.secrets.View', {
    extend: 'Ext.panel.Panel',
    alias: 'widget.pveSecretsView',

    layout: { type: 'vbox', align: 'stretch' },

    initComponent: function() {
        let me = this;
        let canSetup = !!Ext.state.Manager.get('GuiCap')?.dc?.['Sys.Modify'];

        let info = Ext.create('Ext.panel.Panel', {
            bodyPadding: 10,
            border: false,
            html: gettext('Loading...'),
        });
        let grid = Ext.create('Ext.grid.Panel', {
            title: gettext('Nodes'),
            border: false,
            flex: 1,
            hidden: true,
            store: { fields: ['node', 'status', 'voter', 'healthy', 'address'] },
            columns: [
                { header: gettext('Node'), dataIndex: 'node', flex: 1 },
                { header: gettext('Role'), dataIndex: 'status', width: 110 },
                { header: gettext('Voter'), dataIndex: 'voter', width: 80,
                  renderer: Proxmox.Utils.format_boolean },
                { header: gettext('Health'), dataIndex: 'healthy', width: 100,
                  renderer: (v) => v ? '<i class="fa fa-check good"></i> OK'
                      : '<i class="fa fa-times critical"></i> ' + gettext('unhealthy') },
                { header: gettext('Address'), dataIndex: 'address', flex: 1 },
            ],
        });
        let setupBtn = Ext.create('Ext.button.Button', {
            text: gettext('Set up'),
            iconCls: 'fa fa-magic',
            hidden: true,
            disabled: !canSetup,
            handler: () => Ext.create('PVE.secrets.Setup', { onDone: () => me.reload() }).show(),
        });

        let backupBtn = Ext.create('Ext.button.Button', {
            text: gettext('Backup'),
            iconCls: 'fa fa-floppy-o',
            hidden: true,
            disabled: !canSetup,
            handler: () => {
                let win = Ext.create('PVE.secrets.BackupEdit', {
                    listeners: { destroy: () => me.reload() },
                });
                if (me.backupValues) {
                    win.setValues(me.backupValues);
                }
                win.show();
            },
        });
        let backupNowBtn = Ext.create('Ext.button.Button', {
            text: gettext('Back up now'),
            hidden: true,
            disabled: true,
            handler: () => Proxmox.Utils.API2Request({
                url: '/cluster/secrets/backup',
                method: 'POST',
                failure: (r) => Ext.Msg.alert(gettext('Error'), r.htmlStatus),
                success: (r) => Ext.create('Proxmox.window.TaskViewer', {
                    upid: r.result.data,
                    autoShow: true,
                    listeners: { destroy: () => me.reload() },
                }),
            }),
        });
        let backupText = (b) => {
            if (!b || !b.configured) {
                return '<i class="fa fa-exclamation-triangle warning"></i> ' +
                    gettext('no backup storage set');
            }
            let t = Ext.htmlEncode(b.storage) + ', ' + Ext.String.format(gettext('every {0} h, keep {1}'),
                b.interval, b.keep);
            if (b.error) {
                return t + ' <i class="fa fa-times critical"></i> ' + Ext.htmlEncode(b.error);
            }
            let last = b.last ? Proxmox.Utils.render_timestamp(b.last) + ' (' + b.count + ')'
                : gettext('none yet');
            return t + ' &nbsp; <b>' + gettext('Last') + ':</b> ' + last;
        };

        me.reload = function() {
            Proxmox.Utils.API2Request({
                url: '/cluster/secrets/status',
                method: 'GET',
                failure: (r) => info.update(Ext.htmlEncode(r.htmlStatus)),
                success: function(r) {
                    let d = r.result.data;
                    if (!d.initialised) {
                        info.update(gettext('The secret store is not set up yet.') + ' ' +
                            (canSetup ? gettext('Click "Set up" to start it on every node.')
                                : gettext('Ask an administrator (Sys.Modify) to set it up.')));
                        setupBtn.show();
                        backupBtn.hide();
                        backupNowBtn.hide();
                        grid.hide();
                        return;
                    }
                    setupBtn.hide();
                    backupBtn.show();
                    backupNowBtn.show();
                    backupNowBtn.setDisabled(!canSetup || !d.backup?.configured);
                    me.backupValues = d.backup?.configured
                        ? { storage: d.backup.storage, keep: d.backup.keep, interval: d.backup.interval }
                        : undefined;
                    let tol = d.failure_tolerance;
                    let warn = tol === 0
                        ? ' <i class="fa fa-exclamation-triangle warning"></i> ' +
                          gettext('losing any node stops the store') : '';
                    info.update(
                        '<b>' + gettext('Status') + ':</b> ' +
                        (d.available ? (d.healthy ? gettext('healthy') : gettext('unhealthy'))
                            : gettext('unavailable')) +
                        ' &nbsp; <b>' + gettext('Leader') + ':</b> ' + Ext.htmlEncode(d.leader || '-') +
                        ' &nbsp; <b>' + gettext('Failure tolerance') + ':</b> ' + tol + warn +
                        '<br><b>' + gettext('Address') + ':</b> https://' +
                        Ext.htmlEncode((d.name || d.vip.replace(/\/.*/, ''))) + ':8200' +
                        ' &nbsp; <b>' + gettext('This node') + ':</b> ' + Ext.htmlEncode(d.local) +
                        (d.version ? ' (OpenBao ' + Ext.htmlEncode(d.version) + ')' : '') +
                        '<br><b>' + gettext('Backup') + ':</b> ' + backupText(d.backup));
                    grid.getStore().loadData(d.servers || []);
                    grid.show();
                },
            });
        };

        me.tbar = [setupBtn, backupBtn, backupNowBtn, { text: gettext('Reload'), iconCls: 'fa fa-refresh', handler: () => me.reload() }];
        me.items = [info, grid];
        me.callParent();
        me.reload();
    },
});
