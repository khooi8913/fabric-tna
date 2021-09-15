// Copyright 2021-present Open Networking Foundation
// SPDX-License-Identifier: LicenseRef-ONF-Member-Only-1.0
package org.stratumproject.fabric.tna.slicing.cli;

import org.apache.karaf.shell.api.action.Command;
import org.apache.karaf.shell.api.action.lifecycle.Service;
import org.onosproject.cli.AbstractShellCommand;
import org.stratumproject.fabric.tna.slicing.api.SlicingAdminService;

import java.util.Map;

/**
 * Get slice store entries.
 */
@Service
@Command(scope = "fabric-tna", name = "queue-store", description = "Get queue store entries")
public class QueueStoreGetCommand extends AbstractShellCommand {

    @Override
    protected void doExecute() {
        SlicingAdminService slicingAdminService = getService(SlicingAdminService.class);
        slicingAdminService.getQueueStore().entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(e -> {
            print("%s -> %s", e.getKey(), e.getValue());
        });
    }
}