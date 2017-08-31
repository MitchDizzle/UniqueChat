#pragma semicolon 1

StringMap mapChatLookup[MAXPLAYERS+1];
int cacheChatCount[MAXPLAYERS+1];

ConVar cDisplay;
ConVar cCacheTime;
ConVar cStoreMax;
ConVar cIgnoreFlag;
int flagBits;

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
    name = "Unique Chat",
    author = "MitchDizzle",
    description = "Prevents players from spamming chat messages that are not unique.",
    version = PLUGIN_VERSION,
    url = "mtch.tech"
}

public void OnPluginStart() {
    LoadTranslations("UniqueChat.phrases");
    CreateConVar("sm_uniquechat_version", PLUGIN_VERSION, "Unique Chat - Prevents players from spamming chat messages that are not unqiue.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    cDisplay = CreateConVar("sm_uniquechat_display", "1", "Display a chat message, 0 - Off, 1 - Telling the message is redundant, 2 - Displays the time before they can say it again.");
    cCacheTime = CreateConVar("sm_uniquechat_time", "120", "The maximum amount of time to store a chat message, 0 to disable time checking");
    cStoreMax = CreateConVar("sm_uniquechat_max", "60", "The maximum amount of chat messages to store in the cache");
    cIgnoreFlag = CreateConVar("sm_uniquechat_ignoreflag", "b", "If the user has this flag then they are ignored from any checks. -1 - Ignore every one (Disables this plugin), 0 - Ignores no one."); 
    cIgnoreFlag.AddChangeHook(IgnoreFlagChanged);
    checkIgnoreFlag();
    AutoExecConfig(true, "UniqueChat");
}

public Action OnClientSayCommand(int client, const char[] command, const char[] message) {
    if(client < 1 || client > MaxClients || flagBits == -1 || (flagBits > 0 && (GetUserFlagBits(client) & flagBits || GetUserFlagBits(client) & ADMFLAG_ROOT))) {
        //Ignore non-players and admins with the ignore flag.
        return Plugin_Continue;
    }
    
    //Trim the message string
    char trimmedMessage[255];
    strcopy(trimmedMessage, sizeof(trimmedMessage), message);
    TrimString(trimmedMessage);
    
    //Check if the cache system is valid, if not then add this message and skip the rest.
    if(mapChatLookup[client] == null) {
        mapChatLookup[client] = new StringMap();
        cacheChatCount[client] = 0;
        addMessageToCache(client, trimmedMessage);
        return Plugin_Continue;
    }
    
    int timestamp = 0;
    if(mapChatLookup[client].GetValue(trimmedMessage, timestamp)) {
        int expireTime = cCacheTime.IntValue;
        if(expireTime == 0) {
            //Message was found in the cache and we're not checking timestamps.
            return Plugin_Stop;
        }
        int validTime = ((GetTime() - timestamp) - expireTime) * -1;
        if(validTime > 0) {
            //Message is passed the expire time
            if(cDisplay.IntValue == 1) {
                PrintToChat(client, "%T", "unique_chat", client);
            } else if(cDisplay.IntValue == 2) {
                PrintToChat(client, "%T", "unique_chat_time", client, validTime);
            }
            return Plugin_Stop;
        }
    }
    //Message is valid
    addMessageToCache(client, trimmedMessage);
    return Plugin_Continue;
}

public void addMessageToCache(int client, const char[] message) {
    int currTime = GetTime();
    mapChatLookup[client].SetValue(message, currTime, true);
    cacheChatCount[client]++;
    //Check if the cache is 'full'
    if(cacheChatCount[client] >= cStoreMax.IntValue) {
        StringMapSnapshot snapshot = mapChatLookup[client].Snapshot();
        char tempBuffer[512];
        int timestamp = 0;
        int expiredTime = cCacheTime.IntValue;
        if(expiredTime != 0) {
            //Method 1: Check all messages and remove expired ones.
            int calcedTime = currTime - expiredTime;
            for(int i = 0; i <= snapshot.Length; i++) {
                timestamp = 0;
                snapshot.GetKey(i, tempBuffer, sizeof(tempBuffer));
                if(mapChatLookup[client].GetValue(tempBuffer,timestamp)) {
                    if(calcedTime < timestamp) {
                        continue;
                    }
                    mapChatLookup[client].Remove(tempBuffer);
                    cacheChatCount[client]--;
                }
            }
        } else {
            //Method 2: Check all messages and remove the oldest one. However StringMapSnapshot doesn't return a list where it's ordered by time added.
            // <asherkin> there is no defined order
            // <asherkin> if you need ordered iteration, store the map keys in an array
            //Mitchell: Well i have a StringMap for each player for storing recent messages, Message is the key and timestamp is the value, I can just look through and find the olded timestamp and remove that entry. Just figured i'd ask if there was an easier method first.
            // <asherkin> there is, use an array
            //So the real question is: Which is faster, StringMaps or ArrayLists?
            int lowestTimeStamp = -1;
            int lowestEntry = -1;
            for(int i = 0; i <= snapshot.Length; i++) {
                timestamp = -1;
                snapshot.GetKey(i, tempBuffer, sizeof(tempBuffer));
                if(mapChatLookup[client].GetValue(tempBuffer,timestamp) && timestamp > 0) {
                    if(lowestTimeStamp == -1 || lowestTimeStamp > timestamp) {
                        lowestTimeStamp = timestamp;
                        lowestEntry = i;
                        continue;
                    }
                }
            }
            if(lowestEntry != -1) {
                snapshot.GetKey(lowestEntry, tempBuffer, sizeof(tempBuffer));
                mapChatLookup[client].Remove(tempBuffer);
                cacheChatCount[client]--;
            }
        }
    }
}

public void OnPlayerDisconnect(int client) {
    if(mapChatLookup[client] != null) {
        delete mapChatLookup[client];
    }
    mapChatLookup[client] = null;
    cacheChatCount[client] = 0;
}

public void IgnoreFlagChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    checkIgnoreFlagString(newValue);
}

public void checkIgnoreFlag() {
    char value[16];
    cIgnoreFlag.GetString(value, sizeof(value));
    checkIgnoreFlagString(value);
}

public checkIgnoreFlagString(const char[] value) {
    if(StrEqual(value, "-1") || StrEqual(value, "0")) {
        flagBits = StringToInt(value);
    } else if(StrEqual(value, "")) {
        flagBits = 0;
    } else {
        flagBits = ReadFlagString(value);
    }
}