from flask import Flask, request, Response
import requests
import boto3
import json
import hashlib
import os
import win32serviceutil
import win32service
import win32event
import servicemanager
import socket
import time

PARAMNAMEPREFIX = "/RL/RG/secure-desktop/auth-token/"
metadata_url = "http://169.254.169.254/latest/meta-data/"
class AppServerSvc (win32serviceutil.ServiceFramework):
    _svc_name_ = "win-nice-dcv-auth-svc"
    _svc_display_name_ = "win-nice-dcv-auth-svc"
    _svc_description_ = "custom authentication service for nice dcv"
    
    def __init__(self,args):
        win32serviceutil.ServiceFramework.__init__(self,args)
        self.hWaitStop = win32event.CreateEvent(None,0,0,None)
        socket.setdefaulttimeout(60)

    def SvcStop(self):
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.hWaitStop)

    def SvcDoRun(self):
        self.ReportServiceStatus(win32service.SERVICE_RUNNING)
        servicemanager.LogMsg(servicemanager.EVENTLOG_INFORMATION_TYPE,
                              servicemanager.PYS_SERVICE_STARTED,
                              (self._svc_name_,''))
        self.app = Flask(__name__)
        self.PORT = 8445
        # self.metadata_url = "http://169.254.169.254/latest/meta-data/"
        self.app.add_url_rule('/', 'index', self.index, methods=['POST'])
        self.app.run(port=self.PORT)

    def index(self):
        try:
            resp = self.validate_user(request)
            # resp = '<auth result="yes"><username>Administrator</username></auth>'
            return Response(resp, status=200, content_type="text/xml")
        except Exception as e:
            print("An error occurred while authenticating user", e)

    def validate_user(self, req):
        try:
            # Get the region from metadata to form SSM object.
            url_to_get_region = f"{metadata_url}placement/region"
            region = self.get_instance_metadata(url_to_get_region)
            ssm_util_obj = SSMUtil(region)

            # Get Parameter from parameter store and retrieve sessionId and authenticationToken
            parameter_value = ssm_util_obj.get_parameter_value()
            auth_data = json.loads(parameter_value['Parameter']['Value'])
            authentication_token = auth_data['auth_token']
            session_id = auth_data['session_id']
            print(f"authToken : {authentication_token}")
            print(f"sessionId : {session_id}")
            
            # return session_id
            # Authenticate the user and rotate the authenticationToken
            if session_id == req.form['sessionId'] and authentication_token == req.form['authenticationToken']:
                self.rotate_token(ssm_util_obj, session_id)
                return '<auth result="yes"><username>Administrator</username></auth>'
            else:
                return '<auth result="no"><username>Administrator</username></auth>'
        except Exception as e:
            print("Error user authentication:", e)
            servicemanager.LogMsg(servicemanager.EVENTLOG_INFORMATION_TYPE, 
                                servicemanager.PYS_SERVICE_STARTED,                             
                                (self._svc_name_, e))

    def rotate_token(self, ssm_util_obj, session_id):
        try:
            new_auth_token = hashlib.sha256(os.urandom(32)).hexdigest()
            print(new_auth_token)
            value_to_store = json.dumps({"auth_token": new_auth_token, "session_id": session_id})
            ssm_util_obj.put_parameter_value(value_to_store)
        except Exception as e:
            print("Error occurred while changing the authenticationToken:", e)

    def get_instance_metadata(self, metadata_url):
        try:
            response = requests.get(metadata_url)
            return response.text
        except Exception as e:
            print(f"Error retrieving metadata: {e}")

class SSMUtil:
    def __init__(self, region):
        self.ssm = boto3.client('ssm', region_name=region)

    # Get values from parameter store
    def get_parameter_value(self):
        try:
            # metadata_url = "http://169.254.169.254/latest/meta-data/"
            url_to_get_instance_id = f"{metadata_url}instance-id"
            instance_id = self.get_instance_metadata(url_to_get_instance_id)
            param_name = f"{PARAMNAMEPREFIX}{instance_id}"
            return self.ssm.get_parameter(Name=param_name, WithDecryption=True)
            # return param_name
        except Exception as e:
            print("Error getting parameter value from SSM parameter store:", e)
            servicemanager.LogMsg(servicemanager.EVENTLOG_INFORMATION_TYPE, 
                                servicemanager.PYS_SERVICE_STARTED,                             
                                (self._svc_name_, e))
    # Store values to parameter store
    def put_parameter_value(self, value):
        try:
            
            url_to_get_instance_id = f"{metadata_url}instance-id"
            instance_id = self.get_instance_metadata(url_to_get_instance_id)
            param_name = f"{PARAMNAMEPREFIX}{instance_id}"
            self.ssm.put_parameter(Name=param_name, Value=value, Type="String", Overwrite=True)
        except Exception as e:
            print("Error occurred while changing authenticationToken:", e)
            servicemanager.LogMsg(servicemanager.EVENTLOG_INFORMATION_TYPE, 
                                servicemanager.PYS_SERVICE_STARTED,                             
                                (self._svc_name_, e))

    def get_instance_metadata(self, metadata_url):
        try:
            response = requests.get(metadata_url)
            return response.text
        except Exception as e:
            print(f"Error retrieving metadata: {e}")

if __name__ == '__main__':
    win32serviceutil.HandleCommandLine(AppServerSvc)
