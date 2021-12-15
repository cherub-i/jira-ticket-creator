#!/bin/bash

usage_and_exit() {
    echo
    echo -e "Error: $1"
    echo 
    echo "Usage: " $(basename "$0") "PROJEKT_KEY TICKET_FILE.json [GRUPPE]"
    echo "Create issues in JIRA."
    echo
    echo "Mandatory arguments:"
    echo "  PROJEKT_KEY             JIRA project key, the project where "
    echo "                            the issues should be created."
    echo "  TICKET_FILE.json        JSON-File containing the issues to "
    echo "                            be created."
    echo
    echo "Optional arguments:"
    echo "  GROUP                   Filter-string, if handed in, only issues "
    echo "                            which contain this string as 'Gruppe'"
    echo "                            are created."
    exit 1
}

error_and_exit() {
    echo
    echo -e "Error: $1"
    echo
    exit 1
}

check_dependencies() {
    which $1 >> /dev/null
    if [ $? != 0 ]; then
        error_and_exit "Missing dependency \n$1 ($2) \nThe Dependency muss be available from the path."
    fi
}

# dependencies
check_dependencies jq https://stedolan.github.io/jq/

## config
# general
TICKET_JSON_TMP_FILE="ticket_json.tmp"


CONFIG_FILE="config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# JIRA server
JIRA_BASE_URL=${JIRA_BASE_URL:-'https://my-jira-server.com'}
BOARD_WITH_SPRINTS_ID=${BOARD_WITH_SPRINTS_ID:-1234}
USER_AUTH=${USER_AUTH:-'BASE64-OF-USER:PASSWORD'}

# user authentication
if [ -z  $USER_AUTH ]; then
    error_and_exit "Credentials for ${JIRA_BASE_URL} have to be stored in USER_AUTH as a base64 encoding of '<USER>:<PASSWORD>'."
fi


# check if called properly
case "$#" in 
0)
    usage_and_exit "Missing mandatory attributes: PROJEKT_KEY  TICKET_FILE.json"
    ;;
1)
    usage_and_exit "Missing mandatory attributes: TICKET_FILE.json"
    ;;
2)
    GRUPPE=""
    ;;
3)  
    GRUPPE=$3
    ;;
esac
# IMPROVE: detect invalid project
TARGET_PROJECT=$1
TICKETS_FILE="$2"

# start
HTTP_RESULT_CODE=$(curl -X GET \
    -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Basic ${USER_AUTH}" \
    -H "Content-Type: application/json" \
    ${JIRA_BASE_URL}/rest/api/2/issue/createmeta)
if [ $HTTP_RESULT_CODE != 200 ]; then
    error_and_exit "Die Credentials aus der Environment-Variable MSI_CONFLUENCE_USER_AUTH wurden \nvon ${JIRA_BASE_URL} nicht angenommen."
fi

# show and then select sprint
SPRINTS_JSON=$(curl -X GET \
    -s \
    -H "Authorization: Basic ${USER_AUTH}" \
    -H "Accept: application/json" \
    -G \
    -d "state=future,active" \
    ${JIRA_BASE_URL}/rest/agile/1.0/board/${BOARD_WITH_SPRINTS_ID}/sprint)

# echo $SPRINTS_JSON
echo "Sprints on board ${BOARD_WITH_SPRINTS_ID}:"
echo $SPRINTS_JSON | jq -r '.values | .[] | "- \(.name), (\(.state)) (\(.id))"'
echo

RE_NUMERIC='^[0-9]+$'
# IMPROVE: detect invalid sprint
while [[ ! $SPRINT_NO =~ $RE_NUMERIC ]] ; do
    read -p "In which sprint should the issues be created (enter sprint number)? " SPRINT_NO
done
SPRINT_ID=$(echo "$SPRINTS_JSON" | jq -r ".values | .[] | select(.name | contains(\"${SPRINT_NO}\") ) | .id")
SPRINT_NAME=$(echo "$SPRINTS_JSON" | jq -r ".values | .[] | select(.name | contains(\"${SPRINT_NO}\") ) | .name")
echo 
echo 


# final confirmation
echo "Do you want to create these issues:"
echo "  project: ${TARGET_PROJECT}"
echo "  sprint:  ${SPRINT_NAME}"
echo "  issues: "
for TICKET in $(jq -r ".tickets | .[] | select(.Gruppe | contains(\"${GRUPPE}\")) | @base64" "$TICKETS_FILE"); do
    TICKET_JSON=$(echo "$TICKET" | base64 -di)
    TICKET_JSON=$(sed -e "s/<SPRINT_NO>/${SPRINT_NO}/g" <<< $TICKET_JSON)
    TICKET_JSON=$(sed -e "s/\"\$SPRINT_ID\"/${SPRINT_ID}/g" <<< $TICKET_JSON)

    TICKET_TITLE=$(echo "$TICKET_JSON" | jq -r ' .Summary')
    echo "  - ${TICKET_TITLE}"
done

PS3="Please choose: "
select opt in "Yes" "Cancel"; do 
    case "$REPLY" in
    1)  # Yes
        break
        ;;
    2)
        exit 0
        ;;
    *) echo "Invalid choice, please choose again.";continue;;
    esac
done
echo


# create tickets
for TICKET in $(jq -r ".tickets | .[] | select(.Gruppe | contains(\"${GRUPPE}\")) | @base64" "$TICKETS_FILE"); do
    TICKET_JSON=$(echo "$TICKET" | base64 -di)
    TICKET_JSON=$(sed -e "s/<SPRINT_NO>/${SPRINT_NO}/g" <<< $TICKET_JSON)
    TICKET_JSON=$(sed -e "s/\"<SPRINT_ID>\"/${SPRINT_ID}/g" <<< $TICKET_JSON)

    TICKET_TITLE=$(echo "$TICKET_JSON" | jq -r ' .Summary')
    echo "Creating issue: \"${TICKET_TITLE}\" ..."

    # build json for ticket
    echo "$TICKET_JSON" | jq -r "{fields: { 
        project: {key: \"${TARGET_PROJECT}\"}, 
        issuetype: {name: .\"Issue Type\"},
        priority: {name: .\"Priority\"},
        summary: .Summary,
        description: .Description,
        labels: .Labels,
        customfield_10006: .\"Epic Link\",
        customfield_10002: .\"Story Points\",
        customfield_10005: .Sprint
    } }" > "$TICKET_JSON_TMP_FILE"
    # cat "$TICKET_JSON_TMP_FILE"

    # create the ticket
    RESULT=$(curl -X POST \
        --progress-bar \
        -H "Authorization: Basic ${USER_AUTH}" \
        -H "Content-Type: application/json; charset=utf-8" \
        --data @"$TICKET_JSON_TMP_FILE" \
        ${JIRA_BASE_URL}/rest/api/2/issue/)
    # echo $RESULT
    rm "$TICKET_JSON_TMP_FILE"

    NEW_TICKET_KEY=$(echo $RESULT | jq -r '.key')
    if [ -z $NEW_TICKET_KEY ]; then
        echo ".. error creating the issue: "
        echo "$RESULT"
    else
        echo "... $NEW_TICKET_KEY (${JIRA_BASE_URL}/browse/$NEW_TICKET_KEY)"
        echo
    fi
done
