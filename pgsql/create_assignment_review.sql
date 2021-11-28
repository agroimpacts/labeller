-- Create assignment_review table in database, and reviewed_count column to 
-- assignment_data
-- Run:
--    psql -f create_assignment_review.sql -U postgis Africa

CREATE TABLE assignment_review (
    reviewer_id integer, 
    review_time timestamp,
    binary_group integer NOT NULL,
    edge_error_count integer,
    edge_error_ratio real, 
    edge_comment varchar(30),
    rid serial NOT NULL,
    assignment_id integer,
    CONSTRAINT rid_key PRIMARY KEY (rid), 
    CONSTRAINT fk_reviewer_id 
        FOREIGN KEY (reviewer_id)
            REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_assignment_id 
        FOREIGN KEY (assignment_id)
            REFERENCES assignment_data(assignment_id) ON DELETE CASCADE,
    CONSTRAINT binary_group_check
        CHECK (binary_group >= 1 AND binary_group <= 5),
    CONSTRAINT edge_error_count_check
         CHECK (edge_error_count >= 0 AND edge_error_count <= 10),
    CONSTRAINT edge_error_percentage 
        CHECK (edge_error_ratio >= 0.0::double precision AND 
               edge_error_ratio <= 1.0::double precision),
    CONSTRAINT edge_comment_check
        CHECK (edge_error_count IS NOT NULL OR edge_error_ratio IS NOT NULL OR 
               edge_comment IS NOT NULL),
    CONSTRAINT reviewer_id_assignment_id_unique 
        UNIQUE (reviewer_id, assignment_id)
);

-- add comment to binary_group column
comment on column assignment_review.binary_group is '
Label group index for binary classification in range [1, 5], where:
1 refers to correctly classified field over all fields is lower than 65%
2 refers to the proportion between 65%- 80%
3 refers to the proportion over 80%
4 refers to 100% correct grid but it only have negative class
5 refers to the proportion <65% but lacks land cover types for modeling
'

-- add reviewed_count column with comment to assignment_data column
-- will fail if column already exists
ALTER TABLE assignment_data 
ADD COLUMN reviewed_count integer DEFAULT 0;

-- add comment
comment on column assignment_data.reviewed_count is '
Number of times this assignment has been reviewed
'