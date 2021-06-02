import sendgrid
import os
from sendgrid.helpers.mail import Mail, Email, To, Content, Attachment, FileContent, FileName, FileType, Disposition
import getopt
import sys
import base64

def usage():
    print (sys.argv[0] + ' -k <SENDGRID_API_KEY> -f <from email> -t <to email> -s <subject> -m <message> -a <attachment file>')

try:
    opts, args = getopt.getopt(sys.argv[1:], "hk:f:t:s:m:a:")
except getopt.GetoptError as err:
    print(err)
    usage()
    sys.exit(2)
efrom = None
eto = None
subject = None
message = None
verbose = False
key = None
attach_files = []
for o,a in opts:
    if o in ("-h", "--help"):
        usage()
        sys.exit()
    elif o in ("-k", "--key"):
        efrom = a
    elif o in ("-f", "--from"):
        efrom = a
    elif o in ("-t", "--to"):
        eto = a
    elif o in ("-a", "--attach"):
        attach_files.append(a)
    elif o in ("-s", "--subject"):
        subject = a
    elif o in ("-m", "--message"):
        message = a
    else:
        assert False, "unhandled option"
            
sg = sendgrid.SendGridAPIClient(api_key=key)
from_email = Email(efrom)
to_email = To(eto)
content = Content("text/html", message)
mail = Mail(from_email, to_email, subject, content)

file_types = {
        '.log': 'text/plain',
        '.txt': 'text/plain',
        '.tar': 'application/x-tar'
}
if (len(attach_files) > 0):
    for fn in attach_files:
        with open(fn, 'rb') as f:
            data = f.read()
            f.close()
            encoded_file = base64.b64encode(data).decode()

            split_tup = os.path.splitext(fn)
            ext = split_tup[1]
            ftype = file_types.get(ext, 'text/plain')
            attachedFile = Attachment(
                FileContent(encoded_file),
                FileName(os.path.basename(fn)),
                FileType(ftype),
                Disposition('attachment')
            )
            mail.add_attachment(attachedFile)

# Get a JSON-ready representation of the Mail object
mail_json = mail.get()

# Send an HTTP POST request to /mail/send
response = sg.client.mail.send.post(request_body=mail_json)
print(response.status_code)
print(response.headers)
