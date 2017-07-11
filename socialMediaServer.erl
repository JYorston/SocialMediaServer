-module(assessment4n).
-compile([export_all]).


% Receives a like or create post from client
% Gets a response from intermediate with Data
% Post liked sucessfully or post created sucessfully
% Sends response back to client
likeServer(Inter) ->
    receive
        {like, Post, Client} -> Inter ! {like, Post},
            receive
              {Data, dbUpdate} ->
                case isPost(Data, Post) of
                  true -> L = numOfLikes(Data, Post),
                          Client!{likes, L+1},
                          likeServer(Inter);

                  false -> Client!{nopost},
                           likeServer(Inter)
                end
            end;
          {post, NewPost, Client} -> Inter ! {createNewPost, NewPost, Client},
                                     likeServer(Inter);

          {newPostSuccess, Client} -> Client ! newPostSuccess,
                                      likeServer(Inter)

    end.


numOfLikes([], _Post)                      -> 0;
numOfLikes([{Post, Likes} | _Posts], Post) -> Likes;
numOfLikes([_ | Posts], Post)              -> numOfLikes(Posts, Post).

isPost([], _Post)                  -> false;
isPost([{Post, _} | _Posts], Post) -> true;
isPost([_ | Posts], Post)          -> isPost(Posts, Post).


% An intermediate processes
% When it receives a like post message
% Immediately send cache back to server
% Check how long it has been since last like request was sent
% If okay to send to DB then send
% Otherwise recurse and try again.
% Also receives createNewPost messages creates a mutually exclusive creatingPost processes
% Also receives NewPostSucess message which will reply to server with sucess.
intermediate(DB,Data,LastRequestTime) ->
  receive
    {like, Post}              -> RequestTime = getTimeInMilli(),
                                 server ! {Data, dbUpdate},
                                 TimeDiff = RequestTime - LastRequestTime,
                                 if
                                   TimeDiff >= 500 ->
                                     DB ! {like, Post, self()},
                                     receive
                                      {DBData, liked} -> intermediate(DB,DBData,RequestTime)
                                     end;
                                   TimeDiff < 500 ->
                                     intermediate(DB,Data,RequestTime)
                                 end;


    {createNewPost, NewPost, Client} -> cp ! {createNewPost,NewPost,Client},
                                        intermediate(DB,Data,LastRequestTime);

    {DBData, newPostSuccess, Client} -> server ! {newPostSuccess, Client},
                                        intermediate(DB,DBData,LastRequestTime)

  end.

  % Get the current time in milliseconds
  getTimeInMilli() ->
  {Mega, Sec, Micro} = os:timestamp(),
  (Mega*1000000 + Sec)*1000 + round(Micro/1000).

% Creating post processes
% Waits for a message to create a post
% Sends this request to the DB
% Waits for a response from DB and sends that back to intermediate
% While it waits for the DB it won't accept any other new post creation messages
creatingPost(DB, Inter) ->
receive
  {createNewPost, NewPost, Client} -> DB ! {post, NewPost},
  receive
    {DBUpdate, newPostSuccess} -> Inter ! {DBUpdate, newPostSuccess, Client}
  end
end,
creatingPost(DB,Inter).

% Database recieves messages from intermediate process
% Updates the data and sends it back the intermediate
% If new post message received then create it and send a
% sucess message back to the creating post process
database(Data) ->
    receive
        {like, Post, Inter} ->
            Data2 = likePost(Data,Post),
            Inter ! {Data2, liked},
            io:fwrite("DB: ~w~n", [Data2]),
            database(Data2);
        {post, NewPost} ->
           Data2 = Data ++ [{length(Data), NewPost}],
           cp ! {Data2, newPostSuccess},
           io:fwrite("DB: ~w~n", [Data2]),
           database(Data2)
    end.


likePost([], _Post)                     -> [];
likePost([{Post, Likes} | Posts], Post) -> [{Post, Likes+1} | Posts];
likePost([P | Posts], Post)             -> [P | likePost(Posts, Post)].


% Waits between 0 - 5 seconds
% Chooses a post between 0 and 5
% Likes the posts
% Reports amount of likes on post
% or if no post
client(Username) ->
  timer:sleep(round(rand:uniform(5001) -1)),
  Post = rand:uniform(6) -1,
  server ! {like,Post,self()},
  receive
    {likes, L} -> io:fwrite("~s: ~w Likes on Post ~w ~n",[Username,L,Post]);
    {nopost}   -> io:fwrite("~s: No Post on ~w ~n",[Username,Post])
  end,
  client(Username).


% New Client
% Randomly chooses between writing a new post
% or liking a post
newClient(Username) ->
  timer:sleep(round(rand:uniform(5001) -1)),
  PostOrLike = round(rand:uniform()),
  case PostOrLike of
    1 ->
      Post = rand:uniform(6) -1,
     server ! {like, Post, self()},
      receive
        {likes, L} -> io:fwrite("~s: ~w Likes on Post ~w ~n",[Username,L,Post]);
        {nopost}   -> io:fwrite("~s: No Post on ~w ~n",[Username,Post])
      end;

    0 -> server ! {post, 0, self()},
         receive
           newPostSuccess -> io:fwrite("~s: Created New Post~n",[Username])
         end
  end,
  newClient(Username).


% Get current system time
% Create Data at start of the program there are no posts
% Spawn the Database with the database
% Spawn an intermediate with its own cache of the database
% Register a server process that communicates between client and intermediate
% Regesiter a mutally exclusive creating post progress with the DB and the processID of
% the intermedaite
% Spawn 5 clients that can create new posts or like posts
program() ->
  CurrentTime = getTimeInMilli(),
  Data = [],
  DB = spawn(?MODULE,database,[Data]),
  Inter = spawn(?MODULE,intermediate,[DB,Data,CurrentTime]),
  register(server,spawn(?MODULE,likeServer,[Inter])),
  register(cp,spawn(?MODULE,creatingPost,[DB, Inter])),
  spawn(?MODULE,newClient,["James"]),
  spawn(?MODULE,newClient,["Tom"]),
  spawn(?MODULE,newClient,["Peter"]),
  spawn(?MODULE,newClient,["Bob"]),
  spawn(?MODULE,newClient,["Paul"]),
  ok.
