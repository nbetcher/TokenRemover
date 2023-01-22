#!/usr/bin/env python3

# import needed modules
import json
import sys
from datetime import timedelta, datetime

# defining the auth file which will be updated if needed
AUTH_FILE = "/config/.storage/auth"


def date_calc(dt, wkd):
    d = datetime.strptime(dt, '%Y-%m-%d')
    t = timedelta((7 + wkd - d.weekday()) % 7)
    return (d + t).strftime('%Y-%m-%d')



def reoccurrence(automation_time, automation_days):
    # calculate next run date
    #weekdays = []
    #num = -1
    
    weekdays = [day for day in range(len(automation_days)) if automation_days[day] == 'true']
    
    
    #for day in automation_days:
    #    num+=1
    #    if day == "true":
    #        weekdays.append(num)
    
    hr, mnt = int(automation_time[0]), int(automation_time[1])

    for date_value in sorted([date_calc(f'{datetime.now().date()}', day) for day in weekdays]):
        date_list = date_value.split('-')
        yr, mnth, d = int(date_list[0]), int(date_list[1]), int(date_list[2])

        if datetime.now() < datetime(year=yr, month=mnth, day=d, hour=hr, minute=mnt):
            later = datetime(year=yr, month=mnth, day=d, hour=hr, minute=mnt)
            return [f"TokenRemover will run at {later}\n{later - datetime.now()).total_seconds()}"


def tokenremover(retention_days, active_days):
    # read auth file contents to variable
    with open(AUTH_FILE, "r") as f:
        data = json.load(f)

    # create empty list, this is where the "valid" tokens will be stored temporarily
    keep_list = []

    # loop through existing refresh tokens to filter the ones that need to be removed
    for token in data["data"]["refresh_tokens"]:
        
        # only focus on "normal" tokens, and keep other tokens, e.g. "system" and "long lived"
        if token["token_type"] != "normal":
            keep_list.append(token)
            continue
        
        if int(active_days) < 999:
            date_str = token["last_used_at"]
            yr, mnth, d, hr, mnt, scnd = date_str[:date_str.index(".")].translate(date_str.maketrans("T:.", "---")).split("-")
            last_used_date = datetime(int(year), int(mnth), int(d), int(hr), int(mnt))
        
            if last_used_date >= (datetime.now() + timedelta(minutes=30) - timedelta(days=int(active_days))):
                keep_list.append(token)
                continue

        # get creation date, and parse to a comparable format
        date_str = token["created_at"]
        yr, mnth, d, hr, mnt, scnd = date_str[:date_str.index(".")].translate(date_str.maketrans("T:.", "---")).split("-")
        creation_date = datetime(int(year), int(mnth), int(d), int(hr), int(mnt))
        
        # compare the creation date with the exact date time of x days ago
        # add 30 minutes to creation date, to prevent on boot execution (if enabled) to trigger hereafter
        if creation_date >= (datetime.now() + timedelta(minutes=30) - timedelta(days=int(retention_days))):
            keep_list.append(token)

    # detect differences
    removed_tokens = len(data["data"]["refresh_tokens"]) - len(keep_list)
    if removed_tokens > 0:    
        data["data"]["refresh_tokens"] = keep_list
        
        # overwrite refresh_token list in auth file
        with open(AUTH_FILE, "w") as f:
            json.dump(data, f, indent=4)
        
        # "send" return value to bash, so it will run the "ha core restart" command hereafter. The restart is
        # necessary to implement the changes, otherwise the updated file will be restored by Home Assistant RAM.
        print(f"Home Assistant Core will now restart to remove {removed_tokens} token{'' if removed_tokens == 1 else 's'}")
    else:
        print(f"No tokens older than {retention_days} day{'' if retention_days == 1 else 's'} were found")
        
    sys.exit(0)


if __name__ == '__main__':
    if sys.argv[1] == '0':
        # check reoccurrence
        result = reoccurrence(sys.argv[2].split(':'), sys.argv[3:])
        print(result)
    else:
        # run tokenremover
        tokenremover(sys.argv[2], sys.argv[3])
    sys.exit(0)
        
        