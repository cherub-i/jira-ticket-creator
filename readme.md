# jira-ticket-creator

## What it does

jira-ticket-creator is a shell-script, which will query JIRA for the
available sprints, let you choose one of those sprints and then will
create tickets ("issues" in JIRA lingo) in that sprint which are
provided through a JSON file. Ticket-data in the JSON may use the
Sprint-number as a placeholder - so you can create tickets like "Sprint
22 - Release" without having to change the sprint number.

In short: it should take away the boring, repetitive and error-prone
task of creating the same set of tickets over and over again for each
sprint.

## Installation

Apart from the script itself, you need to have
[jq](https://stedolan.github.io/jq/) and available in your standard
path.

You can configure the JIRA URL, board numner and credentials in the
script itself, but I would advise you to create a script `config.sh` in
the same folder as the script and configure the variables there (the
script already supports this - just use the same variable names as in
the script).  
This will make it easier to use the script with different configs and to
pull updates for the script.

## Usage

The script itself will print out usage information if you start it
without the right set of parameters, please refer to that. Take a look
at [```tickets.example.json```](./tickets.example.json) to find out how
to formulate the JSON with the ticktes you want to create.
