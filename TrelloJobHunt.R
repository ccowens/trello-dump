if(!require(trelloR)) {install.packages("trelloR"); library(trelloR)}
if(!require(purrr)) {install.packages("purrr"); library(purrr)}
if(!require(dplyr)) {install.packages("dplyr"); library(dplyr)}
if(!require(writexl)) {install.packages("writexl"); library(writexl)}

# Set up the Trello API connection and get the id for the boatd -----------
my_token = get_token("my-app",
                     key = Sys.getenv("MY_TRELLOAPI_KEY"), 
                     secret = Sys.getenv("MY_TRELLOAPI_SECRET"))

the_board <- get_my_boards() %>% 
  filter(name == "Application Tracker") %>% 
  pull(id)


# Set up lookup tables for list and label ids for the names ---------------

the_list_ids <- get_board_lists(the_board) %>% 
  select(id, name) %>% 
  rename(list=name, idList=id)
the_label_ids <- get_board_labels(the_board) %>% 
  select(id, name) %>% 
  rename(label=name)


# Grab the cards ----------------------------------------------------------

the_cards <- get_board_cards(the_board) %>% 
  select(id,idList,idLabels,name,due,shortUrl,email,desc)


# Figure out the labels for each card -------------------------------------

# The label ids are embedded in a list ordered by card, so we need to flatten
# the list as a vector and then a single-column data frame while still 
# preserving the null slots with no label. This way the associations line up.
assigned_labels <- the_cards$idLabels %>% 
  map_if(is_empty, length) %>% 
  map_if(is.integer, as.character) %>% 
  list_c() %>% 
  as.data.frame(nm="id")

# Replace the ids with the actual label names in another 1-column data frame
# that lines up each label name with the right card. Merge this into the data 
# frame of cards
ordered_labels <- left_join(assigned_labels, the_label_ids) %>% 
  select(-id)

the_cards <- bind_cols(the_cards, ordered_labels) %>% 
  select(-idLabels)


# Look up and replace the list ids ----------------------------------------

the_cards <- left_join(the_cards, the_list_ids) %>% 
  select(-idList)


# Clean up, sort, and save as Excel and CSV  ------------------------------

the_cards <- select(the_cards, -id) %>% 
  mutate(ApplyDate=as.Date(due), .keep="unused") %>% 
  rename(Job=name, LocationType=label, Status=list) %>% 
  filter(Status %in% c("Create/Prep","Applied/Submitted","Interview",
                       "Rejected","Deadpool (After App)")) %>% 
  group_by(ApplyDate) %>% 
  arrange(ApplyDate)

write_xlsx(the_cards, "ApplicationTracker.xlsx")