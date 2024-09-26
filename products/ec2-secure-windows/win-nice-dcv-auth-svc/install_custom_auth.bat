echo "compiling custom auth service"
cd win-nice-dcv-auth-svc
pip install -r .\requirements.txt
echo "deleting win-nice-dcv-auth-svc"
sc.exe delete win-nice-dcv-auth-svc
echo "Installing win-nice-dcv-auth-svc"
python .\win-nice-dcv-auth-svc.py --startup auto install
echo "Starting win-nice-dcv-auth-svc"
python .\win-nice-dcv-auth-svc.py start 
echo "running test for win-nice-dcv-auth-svc \n Expected response : <auth result="No"><username>Administrator</username></auth>"
echo "test result :"
    
