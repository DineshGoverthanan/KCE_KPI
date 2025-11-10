from py_jama_rest_client.client import JamaClient
import pandas as pd
import json
import os

# -----------------------------------------
# Function to recursively find a key in dictionaries/lists
# -----------------------------------------
def dictionary_finder(dictionary, key_to_find):
    if isinstance(dictionary, dict):
        if key_to_find in dictionary:
            return dictionary[key_to_find]
        for value in dictionary.values():
            if isinstance(value, (dict, list)):
                return_value = dictionary_finder(value, key_to_find)
                if return_value is not None:
                    return return_value
    elif isinstance(dictionary, list):
        for item in dictionary:
            return_value = dictionary_finder(item, key_to_find)
            if return_value is not None:
                return return_value
    return None

# -----------------------------------------
# Function to get user details from IDs
# -----------------------------------------
def get_user_data(items, user_dict):
    user_ids = set()
    for item in items:
        assigned_to = dictionary_finder(item, "assignedTo")
        modified_by = dictionary_finder(item, "modifiedBy")
        created_by = dictionary_finder(item, "createdBy")

        if assigned_to:
            user_ids.add(assigned_to)
        if modified_by:
            user_ids.add(modified_by)
        if created_by:
            user_ids.add(created_by)

    for user_id in user_ids:
        try:
            user_info = client.get_user(user_id)
            if user_info:
                user_dict[user_id] = user_info.get("firstName", "Unknown")
        except Exception as e:
            print(f"Error fetching user info for ID {user_id}: {e}")
    return user_dict

# -----------------------------------------
# Filter function to remove items with documentKey starting with "LCE"
# -----------------------------------------
def filter_out_lce(data):
    filtered = []
    for item in data:
        doc_key = dictionary_finder(item, "documentKey")
        if doc_key and not doc_key.startswith("LCE"):
            filtered.append(item)
    return filtered

# -----------------------------------------
# Jama client setup
# -----------------------------------------
host_domain = "https://konerqm.jamacloud.com"
Testrun_filter_id = 7273
Defect_filter_id = 7274

client_ID = os.getenv("JAMA_CLIENT_ID")
client_Secret = os.getenv("JAMA_CLIENT_SECRET")

client = JamaClient(
    host_domain=host_domain,
    credentials=(client_ID, client_Secret),
    oauth=True,
)

# -----------------------------------------
# Fetch raw filter data
# -----------------------------------------
testrun_data = client.get_filter_results(Testrun_filter_id)
defect_data = client.get_filter_results(Defect_filter_id)

print(f"Fetched {len(testrun_data)} test run items")
print(f"Fetched {len(defect_data)} defect items")

# -----------------------------------------
# Save raw JSON data
# -----------------------------------------
with open("raw_testrun_data.json", "w", encoding="utf-8") as f:
    json.dump(testrun_data, f, indent=4)
with open("raw_defect_data.json", "w", encoding="utf-8") as f:
    json.dump(defect_data, f, indent=4)

# Save raw CSV data
pd.DataFrame(testrun_data).to_csv("raw_testrun_data.csv", index=False)
pd.DataFrame(defect_data).to_csv("raw_defect_data.csv", index=False)

print("Raw data saved (JSON & CSV)")

# -----------------------------------------
# Filter data (remove LCE)
# -----------------------------------------
testrun_data_filtered = filter_out_lce(testrun_data)
defect_data_filtered = filter_out_lce(defect_data)

print(f"Filtered test run data: {len(testrun_data_filtered)} items (removed {len(testrun_data) - len(testrun_data_filtered)} LCE items)")
print(f"Filtered defect data: {len(defect_data_filtered)} items (removed {len(defect_data) - len(defect_data_filtered)} LCE items)")

# Save filtered JSON & CSV
with open("filtered_testrun_data.json", "w", encoding="utf-8") as f:
    json.dump(testrun_data_filtered, f, indent=4)
with open("filtered_defect_data.json", "w", encoding="utf-8") as f:
    json.dump(defect_data_filtered, f, indent=4)

pd.DataFrame(testrun_data_filtered).to_csv("filtered_testrun_data.csv", index=False)
pd.DataFrame(defect_data_filtered).to_csv("filtered_defect_data.csv", index=False)

print("Filtered data saved (JSON & CSV)")

# -----------------------------------------
# Process KPI data using filtered datasets
# -----------------------------------------
user_dict = {}
user_dict = get_user_data(testrun_data_filtered + defect_data_filtered, user_dict)

Testrun_data = [
    (
        dictionary_finder(item, "documentKey"),
        user_dict.get(dictionary_finder(item, "assignedTo")),
        dictionary_finder(item, "executionDate")
    )
    for item in testrun_data_filtered
]

Defect_data = [
    (
        dictionary_finder(item, "documentKey"),
        user_dict.get(dictionary_finder(item, "createdBy"))
    )
    for item in defect_data_filtered
]

kp_data = {}
for item in Testrun_data + Defect_data:
    user = item[1]
    if user not in kp_data:
        kp_data[user] = {"defect_count": 0, "testrun_count": 0, "Days": set()}
    if item in Testrun_data:
        kp_data[user]["testrun_count"] += 1
        execution_date = item[2] if len(item) > 2 else None
        if execution_date:
            kp_data[user]["Days"].add(execution_date)
    if item in Defect_data:
        kp_data[user]["defect_count"] += 1

# Convert Days set to unique day count
for user in kp_data:
    kp_data[user]["Days"] = len(kp_data[user]["Days"])

# Prepare KPI data
output_data = []
for user, data in kp_data.items():
    output_data.append({
        "User": user,
        "Testrun_count": data["testrun_count"],
        "Defect_count": data["defect_count"],
        "Days": data["Days"],
        "Test case Productivity": round(data["testrun_count"] / max(data["Days"], 1), 2),
        "Defect Observation Rate": round(data["defect_count"] / max(data["testrun_count"], 1), 2),
    })

df_kp = pd.DataFrame(output_data)

# -----------------------------------------
# Extract defect data for CSV
# -----------------------------------------
defect_extracted_data = []
for item in defect_data_filtered:
    fields = item.get("fields", {})
    defect_extracted_data.append({
        "Document Key": fields.get("documentKey"),
        "Name": fields.get("name"),
        "Created By": user_dict.get(fields.get("createdBy")),
        "Found in Build": fields.get("BUG_foundInBuild$154"),
        "Found On Date": fields.get("BUG_foundOnDate$154"),
    })
df_defects = pd.DataFrame(defect_extracted_data)

# -----------------------------------------
# Extract test run data for CSV
# -----------------------------------------
testrun_extracted_data = []
for item in testrun_data_filtered:
    fields = item.get("fields", {})
    testrun_extracted_data.append({
        "TestRunStatus": fields.get("testRunStatus"),
        "ExecutionDate": fields.get("executionDate"),
        "Document Key": fields.get("documentKey"),
        "Name": fields.get("name"),
        "Assigned To": user_dict.get(fields.get("assignedTo")),
    })
df_testruns = pd.DataFrame(testrun_extracted_data)

# -----------------------------------------
# Export KPI and filtered data to CSV/JSON
# -----------------------------------------
df_kp.to_csv("kp_data.csv", index=False)
df_defects.to_csv("defect_data.csv", index=False)
df_testruns.to_json("testrun_data.json", orient="records", indent=4)

print("Data exported to kp_data.csv, defect_data.csv, testrun_data.json")

# Optional: Excel export
output_file = "kp_data.xlsx"
with pd.ExcelWriter(output_file, engine='xlsxwriter') as writer:
    df_kp.to_excel(writer, sheet_name='KP', index=False)
    df_defects.to_excel(writer, sheet_name='Defect', index=False)
    df_testruns.to_excel(writer, sheet_name='Test run', index=False)
print(f"Data exported to {output_file}")
