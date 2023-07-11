update newqaqc_sites set fields='N';
update newqaqc_sites n set fields='Y' 
where exists (select true from qaqcfields q where q.name=n.name);
