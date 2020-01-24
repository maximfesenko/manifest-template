public with sharing class ManifestDefaultTemplateController {
	
	public Service service { get; set; }
	public String logoUrl { get; private set; }

	public void doInit() {
		this.service = new Service();
		Id manifestId = ApexPages.currentPage().getParameters().get('manifestId');
		if (manifestId == null) {
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'There is no required parameter in URL.'));
			return;
		}

		//As KaptioTravel__Itinerary_Item__c records are filtered by KaptioTravel__Manifest__c.KaptioTravel__Item__c so there will be only 1 KaptioTravel__Item__c.KaptioTravel__DevelopmentRecordTypeName__c
		String recordTypeName = '';

		//Query KaptioTravel__Itinerary_Item__c records are related to Manifest__c.Id
		List<KaptioTravel__Itinerary_Item__c> itineraryItems = queryItineraryItemsByManifest(manifestId);
		if (itineraryItems.isEmpty()) {
            return;
		}

        this.service.name = itineraryItems.get(0).KaptioTravel__Item__r.KaptioTravel__ExternalName__c;
        Map<String,Object> pgiSettings = getPgiSettings(itineraryItems.get(0).KaptioTravel__RecordTypeName__c);

		Map<String,List<KaptioTravel__Itinerary_Item__c>> groupedItineraryItems = new Map<String, List<KaptioTravel__Itinerary_Item__c>>();
		Set<Id> itineraryIds = new Set<Id>();
		for (KaptioTravel__Itinerary_Item__c itineraryItem : itineraryItems) {
			itineraryIds.add(itineraryItem.KaptioTravel__Itinerary__c);
			List<KaptioTravel__Itinerary_Item__c> values = groupedItineraryItems.get(itineraryItem.KaptioTravel__Price_Category__r.Name);
			if (values == null) {
				groupedItineraryItems.put(itineraryItem.KaptioTravel__Price_Category__r.Name, new List<KaptioTravel__Itinerary_Item__c>());
			}
			groupedItineraryItems.get(itineraryItem.KaptioTravel__Price_Category__r.Name).add(itineraryItem);
		}

		List<String> queryPassengerFields = (List<String>)pgiSettings.get('passengerFields');
		Map<Id,KaptioTravel__Passenger__c> passengerMap = new Map<Id,KaptioTravel__Passenger__c>((List<KaptioTravel__Passenger__c>)Database.query('SELECT ' + String.join(queryPassengerFields, ',') + ' FROM KaptioTravel__Passenger__c WHERE KaptioTravel__Itinerary__c IN :itineraryIds'));
        Map<String,Map<String,Object>> passengerPgiFields = (Map<String,Map<String,Object>>)pgiSettings.get('passengerPgiFields');

		for (String optionName : groupedItineraryItems.keySet()) {
			OptionInfo option = new OptionInfo();
			option.name = optionName;
			for (KaptioTravel__Itinerary_Item__c itineraryItem : groupedItineraryItems.get(optionName)) {
				for (Integer i = 0; i < itineraryItem.KaptioTravel__Quantity__c; i++) {
					if (itineraryItem.KaptioTravel__Itinerary__r.KaptioTravel__UseLightningVersion__c) {
						option.addLightningLine(itineraryItem, passengerMap, passengerPgiFields, i + 1);
					} else {
						option.addNonLightningLine(itineraryItem, passengerMap, passengerPgiFields);
					}
				}
			}
			this.service.options.add(option);
		}
	}

	private List<KaptioTravel__Itinerary_Item__c> queryItineraryItemsByManifest(Id p_manifestId) {
		Set<Id> itineraryItemIds = new Set<Id>();
		for (KaptioTravel__ManifestItem__c manifestItem : [SELECT KaptioTravel__ItineraryItem__c, KaptioTravel__Manifest__r.KaptioTravel__Item__r.KaptioTravel__ExternalName__c FROM KaptioTravel__ManifestItem__c WHERE KaptioTravel__Manifest__c = :p_manifestId]) {
			itineraryItemIds.add(manifestItem.ItineraryItem__c);
		}

		return [
			SELECT KaptioTravel__Itinerary__r.KaptioTravel__UseLightningVersion__c, KaptioTravel__Itinerary__r.KaptioTravel__BookingNumber__c, KaptioTravel__DateFrom__c, KaptioTravel__TimeFrom__c, KaptioTravel__TimeTo__c, KaptioTravel__PickUpLocation__c, KaptioTravel__DropOffLocation__c, KaptioTravel__PassengerDetails__c, KaptioTravel__Quantity__c, KaptioTravel__Price_Category__r.Name, KaptioTravel__RecordTypeName__c, KaptioTravel__Item__r.KaptioTravel__ExternalName__c,
			(SELECT KaptioTravel__ItineraryItem__r.KaptioTravel__RecordTypeName__c, KaptioTravel__Passenger__c, KaptioTravel__Unit__c FROM KaptioTravel__PassengerItineraryUnitAssignments__r WHERE KaptioTravel__Passenger__c != null)
			FROM KaptioTravel__Itinerary_Item__c
			WHERE Id IN :itineraryItemIds
		];
	}

    private static Map<String,Object> getPgiSettings(String p_recordTypeName) {
		Id pgiSchemeId = [SELECT KaptioTravel__PGIScheme__c FROM KaptioTravel__PriceCategoryType__c WHERE KaptioTravel__RecordTypeKey__c = :p_recordTypeName LIMIT 1].KaptioTravel__PGIScheme__c;
		List<KaptioTravel__PGISchemeAssignment__c> pgiSchemeAssignments = [SELECT KaptioTravel__TargetField__c FROM KaptioTravel__PGISchemeAssignment__c WHERE KaptioTravel__PGIScheme__c = :pgiSchemeId ORDER BY CreatedDate];
		Map<String,Map<String,Object>> passengerPgiFields = new Map<String, Map<String, Object>>();
		List<String> queryPassengerFields = new List<String> {'KaptioTravel__Salutation__c', 'KaptioTravel__FirstName__c', 'KaptioTravel__LastName__c', 'KaptioTravel__Age__c'};
		if ( ! pgiSchemeAssignments.isEmpty()) {
			Map<String,SObjectField> passengerFieldMap = SObjectType.KaptioTravel__Passenger__c.fields.getMap();
			for (KaptioTravel__PGISchemeAssignment__c pgiSchemeAssignment : pgiSchemeAssignments) {
				DescribeFieldResult dfr = passengerFieldMap.get(pgiSchemeAssignment.KaptioTravel__TargetField__c).getDescribe();

				if (dfr.getType() == Schema.DisplayType.PICKLIST || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
					Map<String,Object> picklistValues = new Map<String, Object>();
					for (PicklistEntry entry : dfr.getPicklistValues()) {
						picklistValues.put(entry.getValue(), entry.getLabel());
					}

					passengerPgiFields.put(pgiSchemeAssignment.KaptioTravel__TargetField__c, new Map<String,Object> {
						'type' => dfr.getType(),
						'picklistvalues' => picklistValues
					});
				} else if (dfr.getType() == Schema.DisplayType.REFERENCE) {
					passengerPgiFields.put(pgiSchemeAssignment.TargetField__c, new Map<String,Object> {
						'type' => dfr.getType(),
						'relationshipname' => dfr.getRelationshipName()
					});
					queryPassengerFields.add(dfr.getRelationshipName() + '.Name');
				} else {
					passengerPgiFields.put(pgiSchemeAssignment.KaptioTravel__TargetField__c, new Map<String,Object> {
						'type' => dfr.getType()
					});
				}
				queryPassengerFields.add(pgiSchemeAssignment.KaptioTravel__TargetField__c);
			}
		}
		return new Map<String,Object> {
			'passengerPgiFields' => passengerPgiFields,
			'passengerFields' => queryPassengerFields
		};
	}

	private class Service {
		public String name { get; set; }
		public List<OptionInfo> options { get; set; }
		public List<String> headers { get; set; }

		public Service() {
			this.name = '';
			this.options = new List<OptionInfo>();
			this.headers = new List<String> {
				'Booking Number',
				'Date From',
				'Pick Up Location',
				'Drop Off Location',
				'Passenger Info',
				'PGI Info'
			};
		}
	}

	private class OptionInfo {
		public String name { get; set; }
		public List<List<String>> lines { get; set; }

		public OptionInfo() {
			this.name = '';
			this.lines = new List<List<String>>();
		}

		public void addLightningLine(KaptioTravel__Itinerary_Item__c p_itineraryItem, Map<Id, KaptioTravel__Passenger__c> p_passengerMap, Map<String,Map<String,Object>> p_passengerPgiFields, Integer p_unitIndex) {
			List<String> passengerInfo = new List<String>();
			List<String> pgiInfo = new List<String>();

			for (KaptioTravel__PassengerItineraryUnitAssignment__c assignment : p_itineraryItem.KaptioTravel__PassengerItineraryUnitAssignments__r) {
				if (assignment.KaptioTravel__Unit__c == p_unitIndex) {//assignment for exact Unit by index
					KaptioTravel__Passenger__c pax = p_passengerMap.get(assignment.KaptioTravel__Passenger__c);
					String ageString = (pax.KaptioTravel__Age__c != null) ? ('<br/>AGE: ' + pax.KaptioTravel__Age__c) : '';
					String salutation = (pax.KaptioTravel__Salutation__c != null) ? pax.KaptioTravel__Salutation__c : '';
					String firstName = (pax.KaptioTravel__FirstName__c != null) ? pax.KaptioTravel__FirstName__c : '';
					String lastName = (pax.KaptioTravel__LastName__c != null) ? pax.KaptioTravel__LastName__c : '';
					passengerInfo.add(salutation + ' ' + firstName + ' ' + lastName + ageString);
					pgiInfo.add(String.join(this.getPgiInfo(p_passengerPgiFields, pax), ', '));
				}
			}
			this.addLine(p_itineraryItem, String.join(passengerInfo, '<br/><br/>'), String.join(pgiInfo, '<br/><br/>'));
		}

		public void addNonLightningLine(KaptioTravel__Itinerary_Item__c p_itineraryItem, Map<Id, KaptioTravel__Passenger__c> p_passengerMap, Map<String,Map<String,Object>> p_passengerPgiFields) {
			List<String> passengerInfo = new List<String>();
			List<String> pgiInfo = new List<String>();

			if(String.isNotEmpty(p_itineraryItem.KaptioTravel__PassengerDetails__c)) {
				Map<String,Object> passDetails = (Map<String,Object>)JSON.deserializeUntyped(p_itineraryItem.KaptioTravel__PassengerDetails__c);
				List<Object> passengerTypes = (List<Object>)passDetails.get('passengerTypes');

				Set<Id> passengerIds = new Set<Id>();
				for (Object passengerType : passengerTypes) {
					List<Object> passengerObjects = (List<Object>)((Map<String,Object>)passengerType).get('passengers');
					for (Object passengerInfoObject : passengerObjects) {
						passengerIds.add((Id)((Map<String,Object>)passengerInfoObject).get('Id'));
					}
				}

				for (Id paxId : passengerIds) {
					KaptioTravel__Passenger__c pax = p_passengerMap.get(paxId);
					String ageString = (pax.KaptioTravel__Age__c != null) ? ('<br/>AGE: ' + pax.KaptioTravel__Age__c) : '';
					String salutation = (pax.KaptioTravel__Salutation__c != null) ? pax.KaptioTravel__Salutation__c : '';
					String firstName = (pax.KaptioTravel__FirstName__c != null) ? pax.KaptioTravel__FirstName__c : '';
					String lastName = (pax.KaptioTravel__LastName__c != null) ? pax.KaptioTravel__LastName__c : '';
					passengerInfo.add(salutation + ' ' + firstName + ' ' + lastName + ageString);
					pgiInfo.add(String.join(this.getPgiInfo(p_passengerPgiFields, pax), ', '));
				}
			}
			this.addLine(p_itineraryItem, String.join(passengerInfo, '<br/><br/>'), String.join(pgiInfo, '<br/><br/>'));
		}

		private void addLine(KaptioTravel__Itinerary_Item__c p_itineraryItem, String p_passengerInfo, String p_pgiInfo) {
			this.lines.add(new List<String> {
				(String.isNotEmpty(p_itineraryItem.KaptioTravel__Itinerary__r.KaptioTravel__BookingNumber__c) ? p_itineraryItem.KaptioTravel__Itinerary__r.KaptioTravel__BookingNumber__c : ''),
				((Datetime)p_itineraryItem.KaptioTravel__DateFrom__c).format('dd MMM YYYY'),
				p_itineraryItem.KaptioTravel__TimeFrom__c + ' ' + (String.isNotEmpty(p_itineraryItem.KaptioTravel__PickUpLocation__c) ? p_itineraryItem.KaptioTravel__PickUpLocation__c : ''),
				p_itineraryItem.KaptioTravel__TimeTo__c + ' ' + (String.isNotEmpty(p_itineraryItem.KaptioTravel__DropOffLocation__c) ? p_itineraryItem.KaptioTravel__DropOffLocation__c : ''),
				p_passengerInfo,
				p_pgiInfo
			});
		}

		private List<String> getPgiInfo(Map<String,Map<String,Object>> p_passengerPgiFields, KaptioTravel__Passenger__c p_pax) {
            List<String> passengersPgiInfo = new List<String>();
            for (String passengerFieldName : p_passengerPgiFields.keySet()) {
				if (p_pax.get(passengerFieldName) == null) {
					passengersPgiInfo.add('');
					continue;
				}

                DisplayType fieldType = (DisplayType)(p_passengerPgiFields.get(passengerFieldName)).get('type');
                if (fieldType == DisplayType.PICKLIST) {

                    Map<String, Object> picklistLabelByValue = (Map<String, Object>) (p_passengerPgiFields.get(passengerFieldName)).get('picklistvalues');
                    passengersPgiInfo.add((String) picklistLabelByValue.get((String) p_pax.get(passengerFieldName)));

                } else if (fieldType == DisplayType.MULTIPICKLIST) {
                    List<String> multiPicklistFieldOutput = new List<String>();
                    Map<String, Object> picklistLabelByValue = (Map<String, Object>) (p_passengerPgiFields.get(passengerFieldName)).get('picklistvalues');
                    for (String multiPicklistValue : String.valueOf(p_pax.get(passengerFieldName)).split(';')) {
                        multiPicklistFieldOutput.add((String) picklistLabelByValue.get(multiPicklistValue));
                    }
                    passengersPgiInfo.add(String.join(multiPicklistFieldOutput, '; '));
                } else if (fieldType == DisplayType.DATE || fieldType == DisplayType.DATETIME) {
                    String formattedDate = (Datetime) p_pax.get(passengerFieldName) != null ? ((Datetime)p_pax.get(passengerFieldName)).format('dd MMM YYYY') : '';
                    passengersPgiInfo.add(formattedDate);
				} else if (fieldType == DisplayType.REFERENCE) {
					String fieldRelationshipName = (String)(p_passengerPgiFields.get(passengerFieldName)).get('relationshipname');
					passengersPgiInfo.add((String)p_pax.getSObject(fieldRelationshipName).get('Name'));
                } else {
                    passengersPgiInfo.add(String.valueOf(p_pax.get(passengerFieldName)));
                }
            }
            return passengersPgiInfo;
        }
	}
}