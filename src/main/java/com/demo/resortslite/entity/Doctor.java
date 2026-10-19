package com.demo.resortslite.entity;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.SequenceGenerator;
import javax.persistence.Table;

@Entity
@Table(name="jpa_doctor_info")
public class Doctor {

	@Column(name="doc_id")
	@Id
	//@GeneratedValue(strategy=GenerationType.AUTO)
	@SequenceGenerator(name="gen1",sequenceName="cno_seq",initialValue = 203,allocationSize = 1)
	@GeneratedValue(generator ="gen1",strategy = GenerationType.SEQUENCE)
	private Integer docId;

	@Column(name="doc_name",length=25)
	private String docName;

	@Column(name="specialization",length=20)
	private String specialization;

	@Column(name="income")
	private Double income;

	public Integer getDocId() {
		return docId;
	}

	public void setDocId(Integer docId) {
		this.docId = docId;
	}

	public String getDocName() {
		return docName;
	}

	public void setDocName(String docName) {
		this.docName = docName;
	}

	public String getSpecialization() {
		return specialization;
	}

	public void setSpecialization(String specialization) {
		this.specialization = specialization;
	}

	public Double getIncome() {
		return income;
	}

	public void setIncome(Double income) {
		this.income = income;
	}
}
