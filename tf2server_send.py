import paramiko
import os
import configparser
import time
import datetime
from stat import S_ISDIR, S_ISREG

    
def Upload(sftp_client,osFile,serverPath):
    def converTime(time):
        return datetime.datetime.fromtimestamp(time).strftime('%M:%H %d-%m-%Y')
    prefix = osFile[1]
    osFileSplitted = os.path.split(osFile[0])
    osFileStat = os.stat(osFile[0])
    print("Uploading :",osFileSplitted[-1],"(Last modification :",converTime(osFileStat.st_mtime),")")
    if prefix == "sp":
        serverPath += "/scripting/"
    elif prefix == "smx":
        serverPath += "/plugins/"
    elif prefix == "so":
        serverPath += "/extensions/"
    elif prefix == "cfg":
        serverPath += "/configs/"
    fileServerPath = serverPath + osFileSplitted[1]
    sftp_client.put(osFile[0] ,fileServerPath)
    sftp_client.utime(fileServerPath,(osFileStat.st_atime,osFileStat.st_mtime))

def listClient(remotedir):
    listclient = []
    for root, dirs, files in os.walk(remotedir):
        for name in files:
            prefix = name.split(".")[-1]
            if prefix=="sp" or prefix=="smx" or prefix == "so" or prefix == "cfg":
                listclient.append([os.path.join(root, name),prefix])
    return listclient

def listServer(sftp, remotedir):
    for entry in sftp.listdir_attr(remotedir):
        remotepath = remotedir + "/" + entry.filename
        mode = entry.st_mode
        if S_ISDIR(mode):
            listServer(sftp, remotepath)
        elif S_ISREG(mode):
            serverListFiles.append(remotepath)

################################

print("Beginning upload...")
config = configparser.ConfigParser()
config.read('settings.ini')
ssh_client = paramiko.SSHClient()
ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh_client.connect(hostname = config["USER0"]["ip"], port = config["USER0"]["port"], username = config["USER0"]["user"], password = config["USER0"]["password"])
sftp_client=ssh_client.open_sftp()

serverPath = config["USER0"]["serverpath"]
osPath = config["USER0"]["ospath"]
osListFiles = listClient(osPath)
for osFile in osListFiles:
    Upload(sftp_client,osFile,serverPath)
print("\n------------------------------")
print("DONE")
print("------------------------------")
#time.sleep(5)

