public class LeadStatusBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Status, Status_Claude__c FROM Lead'
        );
    }

    public void execute(Database.BatchableContext bc, List<Lead> leads) {
        for (Lead lead : leads) {
            if (lead.Status == 'Working - Contacted') {
                lead.Status_Claude__c = 'Working';
            } else {
                lead.Status_Claude__c = 'Not Working';
            }
        }
        update leads;
    }

    public void finish(Database.BatchableContext bc) {
    }
}
