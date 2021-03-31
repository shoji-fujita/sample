#!/usr/bin/env python3
from bs4 import BeautifulSoup
import ast
import requests
import requests_html
import re
import sys
# Verify user supplied a YouTube URL.
#if len(sys.argv) == 1:
#   print("Please provide a YouTube URL (e.g. ./YoutubeChatReplayCrawler.py YOUTUBE_VIDEO_URL)")
#   sys.exit(0)
# Produce a valid filename (from Django text utils).
def get_valid_filename(s):
   s = str(s).strip().replace(' ', '_')
   return re.sub(r'(?u)[^-\w.]', '', s)
# Set up variables for requests.
#target_url = sys.argv[1]
target_url = "https://www.youtube.com/watch?v=Q-1p7tewNHw"
dict_str = ''
next_url = ''
comment_data = []
session = requests_html.HTMLSession()
headers = {'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.116 Safari/537.36'}
# Get the video page.
# html = session.get(target_url)
resp = session.get(target_url)
resp.html.render(sleep=3)
# soup = BeautifulSoup(html.text, 'html.parser')
# Retrieve the title and sanitize so it is a valid filename.
title = resp.html.find('title')
title = title[0].text.replace(' - YouTube', '')
title = get_valid_filename(title)
# Regex match for emoji.
RE_EMOJI = re.compile('[\U00010000-\U0010ffff]', flags=re.UNICODE)
# Find any live_chat_replay elements, get URL for next live chat message.
for iframe in resp.html.find("iframe"):
    if "live_chat_replay" in iframe.attrs["src"]:
        next_url = "".join(["https://www.youtube.com", iframe.attrs["src"]])
if not next_url:
   print("Couldn't find live_chat_replay iframe. Maybe try running again?")
   sys.exit(0)
# TODO - We should fail fast if next_url is empty, otherwise you get error:
# Invalid URL '': No schema supplied. Perhaps you meant http://?
# TODO - This loop is fragile. It loops endlessly when some exceptions are hit.
while(1):
   try:
       html = session.get(next_url, headers=headers)
       soup = BeautifulSoup(html.text, 'lxml')
       # Loop through all script tags.
       for script in soup.find_all('script'):
           script_text = str(script)
           if 'ytInitialData' in script_text:
               dict_str = ''.join(script_text.split(" = ")[1:])
            #    print(dict_str)
       # Capitalize booleans so JSON is valid Python dict.
       dict_str = dict_str.replace("false", "False")
       dict_str = dict_str.replace("true", "True")
       # Strip extra HTML from JSON.
       dict_str = re.sub(r'};.*\n.+<\/script>', '}', dict_str)
       # Correct some characters.
       dict_str = dict_str.rstrip(" \n;")
       # TODO: I don't seem to have any issues with emoji in the messages.
       # dict_str = RE_EMOJI.sub(r'', dict_str)
       # Evaluate the cleaned up JSON into a python dict.
       dict_str = dict_str.rstrip(";</script>")
    #    print('aaa: ' + dict_str)
       dics = ast.literal_eval(dict_str)
       # TODO: On the last pass this returns KeyError since there are no more
       # continuations or actions. Should probably just break in that case.
       continue_url = dics["continuationContents"]["liveChatContinuation"]["continuations"][0]["liveChatReplayContinuationData"]["continuation"]
       print('Found another live chat continuation:')
       print(continue_url)
       next_url = "https://www.youtube.com/live_chat_replay?continuation=" + continue_url
       # Extract the data for each live chat comment.
       for samp in dics["continuationContents"]["liveChatContinuation"]["actions"]:
           comment_data.append(str(samp) + "\n")

   except requests.ConnectionError:
       print("Connection Error")
       continue
   except requests.HTTPError:
       print("HTTPError")
       break
   except requests.Timeout:
       print("Timeout")
       continue
   except requests.exceptions.RequestException as e:
       print(e)
       break
   except KeyError as e:
       error = str(e)
       if 'liveChatReplayContinuationData' in error:
           print('Hit last live chat segment, finishing job.')
       else:
           print("KeyError")
           print(e)
       break
   except SyntaxError as e:
       print("SyntaxError")
       print(e)
       break
       # continue #TODO
   except KeyboardInterrupt:
       break
   except Exception:
       print("Unexpected error:" + str(sys.exc_info()[0]))
# Write the comment data to a file named after the title of the video.
with open(title + ".json", mode='w', encoding="utf-8") as f:
   f.writelines(comment_data)
print('Comment data saved to ' + title + '.json')
